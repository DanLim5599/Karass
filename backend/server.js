require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const crypto = require('crypto');
const axios = require('axios');

// Import modular utilities and middleware
const { isValidEmail, isValidUsername, isValidPassword, sanitizeInt, escapeHtml } = require('./utils/validation');
const { initDb } = require('./utils/database');
const { sendPushToTopic } = require('./services/fcm');
const { securityHeaders } = require('./middleware/security');
const { rateLimit, authRateLimit } = require('./middleware/rateLimit');
const { generateToken, requireAuth, createRequireAdmin } = require('./middleware/auth');

const app = express();

// Security constants
const BCRYPT_ROUNDS = 12;

// Create admin middleware with database pool access (initialized after pool creation)
let requireAdmin;

// Validate required environment variables at startup
function validateEnv() {
  const required = ['DATABASE_URL'];
  const missing = required.filter(key => !process.env[key]);
  if (missing.length > 0) {
    console.error(`FATAL: Missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }

  // Note: Admin authentication now uses JWT tokens
  // Users with is_admin=true in database can perform admin operations
}

validateEnv();

// Validate JWT_SECRET is configured (auth operations use middleware/auth.js)
if (!process.env.JWT_SECRET) {
  console.error('FATAL: JWT_SECRET environment variable is required');
  process.exit(1);
}

// Twitter OAuth Configuration
const TWITTER_CLIENT_ID = process.env.TWITTER_CLIENT_ID;
const TWITTER_CLIENT_SECRET = process.env.TWITTER_CLIENT_SECRET;
const TWITTER_CALLBACK_URL = 'karass://callback';

// GitHub OAuth Configuration
const GITHUB_CLIENT_ID = process.env.GITHUB_CLIENT_ID;
const GITHUB_CLIENT_SECRET = process.env.GITHUB_CLIENT_SECRET;
// GitHub requires HTTP/HTTPS callback URL (not custom schemes)
// Use GITHUB_REDIRECT_URL env var for production, or auto-detect for local dev
const GITHUB_REDIRECT_BASE = process.env.GITHUB_REDIRECT_URL || `http://localhost:${process.env.PORT || 3000}`;
const GITHUB_CALLBACK_URL = `${GITHUB_REDIRECT_BASE}/api/auth/github/web-callback`;

// In-memory store for PKCE verifiers (use Redis in production)
const pkceStore = new Map();
const PKCE_TTL = 10 * 60 * 1000; // 10 minutes
const PKCE_MAX_ENTRIES = 1000; // Maximum concurrent OAuth flows

// Clean up expired PKCE entries and enforce max size
setInterval(() => {
  const now = Date.now();
  for (const [state, data] of pkceStore.entries()) {
    if (now - data.createdAt > PKCE_TTL) {
      pkceStore.delete(state);
    }
  }
  // If still over limit after cleanup, remove oldest entries
  if (pkceStore.size > PKCE_MAX_ENTRIES) {
    const entries = [...pkceStore.entries()].sort((a, b) => a[1].createdAt - b[1].createdAt);
    const toRemove = entries.slice(0, pkceStore.size - PKCE_MAX_ENTRIES);
    toRemove.forEach(([state]) => pkceStore.delete(state));
  }
}, 60000); // Clean every minute

// Security: Restrict CORS to specific origins (configure for production)
const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000', 'http://10.0.2.2:3000'];
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps make requests without origin header)
    if (!origin) {
      callback(null, true);
    } else if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true
}));

// Security headers middleware (from module)
app.use(securityHeaders);

// Security: Limit request body size to prevent DoS
app.use(express.json({ limit: '10kb' }));

// Apply rate limiting middleware (from module)
app.use(rateLimit);

// PostgreSQL connection pool with proper configuration
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: true  // Security: Validate SSL certificates
  },
  // Connection pool settings
  max: 20,                    // Maximum connections in pool
  min: 2,                     // Minimum connections to maintain
  idleTimeoutMillis: 30000,   // Close idle connections after 30s
  connectionTimeoutMillis: 5000,  // Fail connection after 5s
  maxUses: 7500               // Close connection after 7500 uses
});

// Handle pool errors to prevent unhandled crashes (e.g., Neon dropping idle connections)
pool.on('error', (err) => {
  console.error('Unexpected database pool error:', err.message);
});

// Initialize admin middleware with database pool
requireAdmin = createRequireAdmin(pool);

// Create Account
app.post('/api/auth/register', authRateLimit, async (req, res) => {
  try {
    const { email, username, password, twitterHandle } = req.body;

    // Input validation
    if (!email || !isValidEmail(email)) {
      return res.status(400).json({ success: false, message: 'Invalid email address' });
    }
    if (!username || !isValidUsername(username)) {
      return res.status(400).json({ success: false, message: 'Username must be 3-30 characters, alphanumeric and underscores only' });
    }
    if (!password || !isValidPassword(password)) {
      return res.status(400).json({ success: false, message: 'Password must be at least 8 characters with uppercase, lowercase, and number' });
    }

    // Check if user exists
    const existingUser = await pool.query(
      'SELECT id, email, username FROM users WHERE LOWER(email) = LOWER($1) OR username = $2',
      [email, username]
    );

    if (existingUser.rows.length > 0) {
      const existing = existingUser.rows[0];
      return res.status(400).json({
        success: false,
        message: existing.email.toLowerCase() === email.toLowerCase()
          ? 'Email already registered'
          : 'Username already taken'
      });
    }

    // Hash password
    const salt = await bcrypt.genSalt(BCRYPT_ROUNDS);
    const hashedPassword = await bcrypt.hash(password, salt);

    // Auto-admin based on environment variable (if configured)
    const adminEmails = process.env.ADMIN_EMAILS ? process.env.ADMIN_EMAILS.toLowerCase().split(',') : [];
    const isAdmin = adminEmails.includes(email.toLowerCase());

    // Create user (auto-approved)
    const result = await pool.query(
      `INSERT INTO users (email, username, password, twitter_handle, is_approved, is_admin)
       VALUES (LOWER($1), $2, $3, $4, TRUE, $5)
       RETURNING id, email, username, twitter_handle, is_approved, is_admin`,
      [email, username, hashedPassword, twitterHandle || null, isAdmin]
    );

    const user = result.rows[0];

    // Generate JWT token
    const token = generateToken(user);

    res.status(201).json({
      success: true,
      message: 'Account created successfully',
      token,
      user: {
        id: user.id.toString(),
        email: user.email,
        username: user.username,
        twitterHandle: user.twitter_handle,
        isApproved: user.is_approved,
        isAdmin: user.is_admin
      }
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Login
app.post('/api/auth/login', authRateLimit, async (req, res) => {
  try {
    const { emailOrUsername, password } = req.body;

    // Input validation
    if (!emailOrUsername || !password) {
      return res.status(400).json({ success: false, message: 'Email/username and password are required' });
    }

    // Find user by email or username
    const result = await pool.query(
      'SELECT id, email, username, password, twitter_handle, is_approved, is_admin FROM users WHERE LOWER(email) = LOWER($1) OR username = $2',
      [emailOrUsername, emailOrUsername]
    );

    if (result.rows.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Invalid credentials'
      });
    }

    const user = result.rows[0];

    // Check password (only for email auth users)
    if (!user.password) {
      return res.status(400).json({
        success: false,
        message: 'Please use Twitter/X or GitHub to sign in'
      });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(400).json({
        success: false,
        message: 'Invalid credentials'
      });
    }

    // Generate JWT token
    const token = generateToken(user);

    res.json({
      success: true,
      message: 'Login successful',
      token,
      user: {
        id: user.id.toString(),
        email: user.email,
        username: user.username,
        twitterHandle: user.twitter_handle,
        isApproved: user.is_approved,
        isAdmin: user.is_admin
      }
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Check approval status
app.get('/api/auth/status/:userId', async (req, res) => {
  try {
    const userId = sanitizeInt(req.params.userId);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }

    const result = await pool.query(
      'SELECT is_approved, is_admin FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const user = result.rows[0];
    res.json({
      success: true,
      isApproved: user.is_approved,
      isAdmin: user.is_admin
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ============================================
// Twitter/X OAuth 2.0 Endpoints
// ============================================

// Initialize Twitter OAuth flow - generates PKCE challenge
app.get('/api/auth/twitter/init', authRateLimit, async (req, res) => {
  try {
    if (!TWITTER_CLIENT_ID) {
      return res.status(500).json({
        success: false,
        message: 'Twitter OAuth not configured'
      });
    }

    // Generate PKCE code verifier (43-128 chars, URL-safe)
    const codeVerifier = crypto.randomBytes(32).toString('base64url');

    // Generate code challenge (SHA256 hash of verifier, base64url encoded)
    const codeChallenge = crypto
      .createHash('sha256')
      .update(codeVerifier)
      .digest('base64url');

    // Generate state parameter for CSRF protection
    const state = crypto.randomBytes(16).toString('hex');

    // Store code verifier temporarily
    pkceStore.set(state, {
      codeVerifier,
      createdAt: Date.now()
    });

    // Build Twitter OAuth URL
    const params = new URLSearchParams({
      response_type: 'code',
      client_id: TWITTER_CLIENT_ID,
      redirect_uri: TWITTER_CALLBACK_URL,
      scope: 'tweet.read users.read offline.access',
      state: state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256'
    });

    const authUrl = `https://twitter.com/i/oauth2/authorize?${params.toString()}`;

    res.json({
      success: true,
      authUrl,
      state,
      codeVerifier
    });
  } catch (error) {
    console.error('Twitter init error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Twitter OAuth callback - exchanges code for tokens
app.post('/api/auth/twitter/callback', authRateLimit, async (req, res) => {
  try {
    const { code, state, codeVerifier } = req.body;

    if (!code || !state || !codeVerifier) {
      return res.status(400).json({
        success: false,
        message: 'Missing required parameters'
      });
    }

    if (!TWITTER_CLIENT_ID || !TWITTER_CLIENT_SECRET) {
      return res.status(500).json({
        success: false,
        message: 'Twitter OAuth not configured'
      });
    }

    // Validate state against stored PKCE data (REQUIRED for CSRF protection)
    const storedData = pkceStore.get(state);
    if (!storedData) {
      return res.status(400).json({
        success: false,
        message: 'Invalid or expired state parameter. Please try again.'
      });
    }
    pkceStore.delete(state); // Clean up after validation

    // Exchange authorization code for access token
    const tokenParams = new URLSearchParams({
      code: code,
      grant_type: 'authorization_code',
      client_id: TWITTER_CLIENT_ID,
      redirect_uri: TWITTER_CALLBACK_URL,
      code_verifier: codeVerifier
    });

    const tokenResponse = await axios.post(
      'https://api.twitter.com/2/oauth2/token',
      tokenParams.toString(),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': `Basic ${Buffer.from(`${TWITTER_CLIENT_ID}:${TWITTER_CLIENT_SECRET}`).toString('base64')}`
        }
      }
    );

    const { access_token } = tokenResponse.data;

    // Fetch Twitter user profile
    const userResponse = await axios.get('https://api.twitter.com/2/users/me', {
      headers: {
        'Authorization': `Bearer ${access_token}`
      },
      params: {
        'user.fields': 'id,name,username,profile_image_url'
      }
    });

    const twitterUser = userResponse.data.data;
    const twitterId = twitterUser.id;
    const twitterUsername = twitterUser.username;
    const twitterName = twitterUser.name;

    // Check if user exists by twitter_id
    let userResult = await pool.query(
      'SELECT id, email, username, twitter_handle, twitter_id, is_approved, is_admin FROM users WHERE twitter_id = $1',
      [twitterId]
    );

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      // Create new user with Twitter auth
      // Generate unique username if needed
      let finalUsername = twitterUsername;
      let suffix = 1;

      while (true) {
        const existingUser = await pool.query(
          'SELECT id FROM users WHERE username = $1',
          [finalUsername]
        );
        if (existingUser.rows.length === 0) break;
        finalUsername = `${twitterUsername}${suffix}`;
        suffix++;
      }

      const insertResult = await pool.query(
        `INSERT INTO users (username, twitter_handle, twitter_id, auth_provider, is_approved, is_admin)
         VALUES ($1, $2, $3, 'twitter', TRUE, FALSE)
         RETURNING id, email, username, twitter_handle, twitter_id, is_approved, is_admin`,
        [finalUsername, `@${twitterUsername}`, twitterId]
      );

      user = insertResult.rows[0];
      isNewUser = true;
      console.log(`Created new Twitter user: ${finalUsername} (Twitter ID: ${twitterId})`);
    } else {
      user = userResult.rows[0];
      console.log(`Existing Twitter user logged in: ${user.username}`);
    }

    // Generate JWT token
    const token = generateToken(user);

    res.json({
      success: true,
      message: isNewUser ? 'Account created successfully' : 'Login successful',
      isNewUser,
      token,
      user: {
        id: user.id.toString(),
        email: user.email || null,
        username: user.username,
        twitterHandle: user.twitter_handle,
        twitterId: user.twitter_id,
        isApproved: user.is_approved,
        isAdmin: user.is_admin
      }
    });
  } catch (error) {
    console.error('Twitter callback error:', error.response?.data || error.message);
    res.status(500).json({
      success: false,
      message: error.response?.data?.error_description || 'Twitter authentication failed'
    });
  }
});

// Link Twitter account to existing email user (optional feature)
app.post('/api/auth/twitter/link', requireAuth, async (req, res) => {
  try {
    const { code, codeVerifier } = req.body;
    const userId = req.user.userId;

    if (!code || !codeVerifier) {
      return res.status(400).json({
        success: false,
        message: 'Missing required parameters'
      });
    }

    // Exchange code for access token (same as callback)
    const tokenParams = new URLSearchParams({
      code: code,
      grant_type: 'authorization_code',
      client_id: TWITTER_CLIENT_ID,
      redirect_uri: TWITTER_CALLBACK_URL,
      code_verifier: codeVerifier
    });

    const tokenResponse = await axios.post(
      'https://api.twitter.com/2/oauth2/token',
      tokenParams.toString(),
      {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': `Basic ${Buffer.from(`${TWITTER_CLIENT_ID}:${TWITTER_CLIENT_SECRET}`).toString('base64')}`
        }
      }
    );

    const { access_token } = tokenResponse.data;

    // Fetch Twitter user profile
    const userResponse = await axios.get('https://api.twitter.com/2/users/me', {
      headers: {
        'Authorization': `Bearer ${access_token}`
      }
    });

    const twitterUser = userResponse.data.data;
    const twitterId = twitterUser.id;
    const twitterUsername = twitterUser.username;

    // Check if this Twitter account is already linked to another user
    const existingLink = await pool.query(
      'SELECT id FROM users WHERE twitter_id = $1 AND id != $2',
      [twitterId, userId]
    );

    if (existingLink.rows.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'This Twitter account is already linked to another user'
      });
    }

    // Link Twitter to user
    await pool.query(
      'UPDATE users SET twitter_id = $1, twitter_handle = $2 WHERE id = $3',
      [twitterId, `@${twitterUsername}`, userId]
    );

    res.json({
      success: true,
      message: 'Twitter account linked successfully',
      twitterHandle: `@${twitterUsername}`
    });
  } catch (error) {
    console.error('Twitter link error:', error.response?.data || error.message);
    res.status(500).json({
      success: false,
      message: 'Failed to link Twitter account'
    });
  }
});

// ============================================
// GitHub OAuth 2.0 Endpoints
// ============================================

// Initialize GitHub OAuth flow - generates PKCE challenge
app.get('/api/auth/github/init', authRateLimit, async (req, res) => {
  try {
    if (!GITHUB_CLIENT_ID) {
      return res.status(500).json({
        success: false,
        message: 'GitHub OAuth not configured'
      });
    }

    // Generate PKCE code verifier (43-128 chars, URL-safe)
    const codeVerifier = crypto.randomBytes(32).toString('base64url');

    // Generate code challenge (SHA256 hash of verifier, base64url encoded)
    const codeChallenge = crypto
      .createHash('sha256')
      .update(codeVerifier)
      .digest('base64url');

    // Generate state parameter for CSRF protection
    const state = crypto.randomBytes(16).toString('hex');

    // Store code verifier temporarily
    pkceStore.set(state, {
      codeVerifier,
      createdAt: Date.now()
    });

    // Build GitHub OAuth URL
    const params = new URLSearchParams({
      client_id: GITHUB_CLIENT_ID,
      redirect_uri: GITHUB_CALLBACK_URL,
      scope: 'read:user user:email',
      state: state,
      code_challenge: codeChallenge,
      code_challenge_method: 'S256'
    });

    const authUrl = `https://github.com/login/oauth/authorize?${params.toString()}`;

    res.json({
      success: true,
      authUrl,
      state,
      codeVerifier
    });
  } catch (error) {
    console.error('GitHub init error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// GitHub OAuth web callback - receives redirect from GitHub, redirects to app
// This is needed because GitHub only supports HTTP/HTTPS redirect URLs, not custom schemes
app.get('/api/auth/github/web-callback', async (req, res) => {
  try {
    const { code, state, error, error_description } = req.query;

    // Build the app redirect URL
    const appRedirectParams = new URLSearchParams();

    if (error) {
      appRedirectParams.set('error', error);
      if (error_description) {
        appRedirectParams.set('error_description', error_description);
      }
    } else if (code && state) {
      appRedirectParams.set('code', code);
      appRedirectParams.set('state', state);
    } else {
      appRedirectParams.set('error', 'missing_params');
      appRedirectParams.set('error_description', 'Missing code or state parameter');
    }

    // Redirect to the app's custom URL scheme
    const appRedirectUrl = `karass://callback?${appRedirectParams.toString()}`;
    console.log('GitHub OAuth: Redirecting to app:', appRedirectUrl);

    // Send HTML that redirects to the app scheme (more reliable than HTTP redirect)
    // Escape URL to prevent XSS attacks
    const safeUrl = escapeHtml(appRedirectUrl);
    res.send(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Redirecting to Karass...</title>
          <meta http-equiv="refresh" content="0;url=${safeUrl}">
        </head>
        <body>
          <p>Redirecting to Karass app...</p>
          <p>If you are not redirected automatically, <a href="${safeUrl}">click here</a>.</p>
          <script>window.location.href = ${JSON.stringify(appRedirectUrl)};</script>
        </body>
      </html>
    `);
  } catch (error) {
    console.error('GitHub web callback error:', error);
    res.status(500).send('Error processing GitHub callback');
  }
});

// GitHub OAuth callback - exchanges code for tokens
app.post('/api/auth/github/callback', authRateLimit, async (req, res) => {
  try {
    const { code, state, codeVerifier } = req.body;

    if (!code || !state || !codeVerifier) {
      return res.status(400).json({
        success: false,
        message: 'Missing required parameters'
      });
    }

    if (!GITHUB_CLIENT_ID || !GITHUB_CLIENT_SECRET) {
      return res.status(500).json({
        success: false,
        message: 'GitHub OAuth not configured'
      });
    }

    // Validate state against stored PKCE data (REQUIRED for CSRF protection)
    const storedData = pkceStore.get(state);
    if (!storedData) {
      return res.status(400).json({
        success: false,
        message: 'Invalid or expired state parameter. Please try again.'
      });
    }

    // Verify code verifier matches stored value (prevents replay attacks)
    if (storedData.codeVerifier !== codeVerifier) {
      pkceStore.delete(state);
      return res.status(400).json({
        success: false,
        message: 'Invalid code verifier. Please try again.'
      });
    }
    pkceStore.delete(state); // Clean up after validation

    // Exchange authorization code for access token (with PKCE code_verifier)
    const tokenResponse = await axios.post(
      'https://github.com/login/oauth/access_token',
      {
        client_id: GITHUB_CLIENT_ID,
        client_secret: GITHUB_CLIENT_SECRET,
        code: code,
        redirect_uri: GITHUB_CALLBACK_URL,
        code_verifier: codeVerifier  // Required for PKCE
      },
      {
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        timeout: 10000  // 10 second timeout
      }
    );

    const { access_token, error, error_description } = tokenResponse.data;

    if (error || !access_token) {
      console.error('GitHub token error:', error, error_description);
      return res.status(400).json({
        success: false,
        message: error_description || 'Failed to get access token from GitHub'
      });
    }

    // Fetch GitHub user profile
    const userResponse = await axios.get('https://api.github.com/user', {
      headers: {
        'Authorization': `Bearer ${access_token}`,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Karass-App'  // GitHub API requires User-Agent
      },
      timeout: 10000  // 10 second timeout
    });

    const githubUser = userResponse.data;
    const githubId = String(githubUser.id);
    // Sanitize GitHub username: only allow alphanumeric, hyphens (GitHub's own rules)
    const githubUsername = (githubUser.login || '').replace(/[^a-zA-Z0-9-]/g, '').substring(0, 30);
    const githubEmail = githubUser.email;

    if (!githubId || !githubUsername) {
      return res.status(400).json({
        success: false,
        message: 'Invalid GitHub user data received'
      });
    }

    // Check if user exists by github_id
    let userResult = await pool.query(
      'SELECT id, email, username, twitter_handle, twitter_id, github_handle, github_id, is_approved, is_admin FROM users WHERE github_id = $1',
      [githubId]
    );

    let user;
    let isNewUser = false;

    if (userResult.rows.length === 0) {
      // Create new user with GitHub auth using transaction for race condition safety
      const client = await pool.connect();
      try {
        await client.query('BEGIN');

        // Generate unique username with retry logic
        let finalUsername = githubUsername;
        let suffix = 1;
        const maxAttempts = 100;

        while (suffix <= maxAttempts) {
          try {
            const insertResult = await client.query(
              `INSERT INTO users (username, email, github_handle, github_id, auth_provider, is_approved, is_admin)
               VALUES ($1, $2, $3, $4, 'github', TRUE, FALSE)
               RETURNING id, email, username, twitter_handle, twitter_id, github_handle, github_id, is_approved, is_admin`,
              [finalUsername, githubEmail || null, `@${githubUsername}`, githubId]
            );
            user = insertResult.rows[0];
            isNewUser = true;
            await client.query('COMMIT');
            console.log(`Created new GitHub user: ${finalUsername} (GitHub ID: ${githubId})`);
            break;
          } catch (insertError) {
            // Check if it's a unique constraint violation on username
            if (insertError.code === '23505' && insertError.constraint && insertError.constraint.includes('username')) {
              finalUsername = `${githubUsername}${suffix}`;
              suffix++;
              continue;
            }
            // Check if it's a unique constraint violation on github_id (user already exists)
            if (insertError.code === '23505' && insertError.constraint && insertError.constraint.includes('github_id')) {
              await client.query('ROLLBACK');
              // User was created by another request, fetch them
              userResult = await pool.query(
                'SELECT id, email, username, twitter_handle, twitter_id, github_handle, github_id, is_approved, is_admin FROM users WHERE github_id = $1',
                [githubId]
              );
              if (userResult.rows.length > 0) {
                user = userResult.rows[0];
                isNewUser = false;
              }
              break;
            }
            await client.query('ROLLBACK');
            throw insertError;
          }
        }

        if (!user && suffix > maxAttempts) {
          await client.query('ROLLBACK');
          return res.status(500).json({
            success: false,
            message: 'Failed to generate unique username'
          });
        }
      } catch (txError) {
        await client.query('ROLLBACK');
        throw txError;
      } finally {
        client.release();
      }
    } else {
      user = userResult.rows[0];
      console.log(`Existing GitHub user logged in: ${user.username}`);
    }

    // Generate JWT token
    const token = generateToken(user);

    res.json({
      success: true,
      message: isNewUser ? 'Account created successfully' : 'Login successful',
      isNewUser,
      token,
      user: {
        id: user.id.toString(),
        email: user.email || null,
        username: user.username,
        twitterHandle: user.twitter_handle,
        twitterId: user.twitter_id,
        githubHandle: user.github_handle,
        githubId: user.github_id,
        isApproved: user.is_approved,
        isAdmin: user.is_admin
      }
    });
  } catch (error) {
    console.error('GitHub callback error:', error.response?.data || error.message);
    res.status(500).json({
      success: false,
      message: error.response?.data?.message || 'GitHub authentication failed'
    });
  }
});

// Admin: Approve user
app.post('/api/admin/approve/:userId', requireAdmin, async (req, res) => {
  try {
    const userId = sanitizeInt(req.params.userId);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }

    await pool.query('UPDATE users SET is_approved = TRUE WHERE id = $1', [userId]);

    const result = await pool.query(
      'SELECT id, email, username, is_approved FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const user = result.rows[0];
    res.json({
      success: true,
      message: 'User approved',
      user: {
        id: user.id.toString(),
        email: user.email,
        username: user.username,
        isApproved: user.is_approved
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Admin: Set user as admin
app.post('/api/admin/set-admin/:userId', requireAdmin, async (req, res) => {
  try {
    const userId = sanitizeInt(req.params.userId);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }

    await pool.query('UPDATE users SET is_admin = TRUE WHERE id = $1', [userId]);

    const result = await pool.query(
      'SELECT id, email, username, is_admin FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    const user = result.rows[0];
    res.json({
      success: true,
      message: 'User is now admin',
      user: {
        id: user.id.toString(),
        email: user.email,
        username: user.username,
        isAdmin: user.is_admin
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Create announcement (admin only - uses JWT authentication)
app.post('/api/announcements', requireAdmin, async (req, res) => {
  try {
    const { message, startsAt, expiresAt, imageUrl } = req.body;
    const adminUserId = req.adminId; // Set by requireAdmin middleware

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      return res.status(400).json({ success: false, message: 'Message is required' });
    }
    if (message.length > 1000) {
      return res.status(400).json({ success: false, message: 'Message too long (max 1000 chars)' });
    }

    // Validate imageUrl if provided (must be a data URL or https URL)
    if (imageUrl && typeof imageUrl === 'string') {
      if (!imageUrl.startsWith('data:image/') && !imageUrl.startsWith('https://')) {
        return res.status(400).json({ success: false, message: 'Invalid image URL format' });
      }
    }

    // Validate dates if provided
    let startsAtDate = startsAt ? new Date(startsAt) : new Date();
    let expiresAtDate = expiresAt ? new Date(expiresAt) : null;

    if (startsAt && isNaN(startsAtDate.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid startsAt date format' });
    }
    if (expiresAt && isNaN(expiresAtDate.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid expiresAt date format' });
    }

    // Delete all existing announcements (only keep one at a time)
    await pool.query('DELETE FROM announcements');

    // Create announcement (sanitize message)
    const sanitizedMessage = message.trim();
    const result = await pool.query(
      `INSERT INTO announcements (message, created_by, starts_at, expires_at, image_url)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, message, created_at, starts_at, expires_at, image_url`,
      [sanitizedMessage, adminUserId, startsAtDate, expiresAtDate, imageUrl || null]
    );

    const announcement = result.rows[0];

    // Send push notification to all users subscribed to 'announcements' topic
    await sendPushToTopic('announcements', 'New Announcement', message, {
      announcementId: String(announcement.id)
    });

    res.status(201).json({
      success: true,
      message: 'Announcement created',
      announcement: {
        id: String(announcement.id),
        message: announcement.message,
        createdAt: announcement.created_at,
        startsAt: announcement.starts_at,
        expiresAt: announcement.expires_at,
        imageUrl: announcement.image_url
      }
    });
  } catch (error) {
    console.error('Create announcement error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Get announcements (only active ones - started and not expired)
app.get('/api/announcements', async (req, res) => {
  try {
    // Validate and limit the limit parameter (max 100)
    let limit = sanitizeInt(req.query.limit) || 20;
    limit = Math.min(Math.max(1, limit), 100);

    // Only return announcements that have started and haven't expired
    const result = await pool.query(`
      SELECT a.id, a.message, a.created_at, a.starts_at, a.expires_at, a.image_url, u.username as created_by_username
      FROM announcements a
      LEFT JOIN users u ON a.created_by = u.id
      WHERE a.starts_at <= NOW()
        AND (a.expires_at IS NULL OR a.expires_at > NOW())
      ORDER BY a.created_at DESC
      LIMIT $1
    `, [limit]);

    res.json({
      success: true,
      announcements: result.rows.map(row => ({
        id: row.id.toString(),
        message: row.message,
        createdAt: row.created_at,
        startsAt: row.starts_at,
        expiresAt: row.expires_at,
        imageUrl: row.image_url,
        createdBy: row.created_by_username
      }))
    });
  } catch (error) {
    console.error('Get announcements error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ============================================
// Beacon Management Endpoints
// ============================================

// Admin: Set a user as the current beacon
app.post('/api/beacon/set/:userId', requireAdmin, async (req, res) => {
  try {
    const userId = sanitizeInt(req.params.userId);
    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }

    // Check if user exists
    const userCheck = await pool.query('SELECT id, username FROM users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // Clear all existing beacon assignments
    await pool.query('UPDATE users SET is_current_beacon = FALSE');

    // Set the new beacon user
    await pool.query('UPDATE users SET is_current_beacon = TRUE WHERE id = $1', [userId]);

    const user = userCheck.rows[0];
    console.log(`Beacon assigned to user: ${user.username} (ID: ${userId})`);

    res.json({
      success: true,
      message: `Beacon assigned to ${user.username}`,
      beaconUser: {
        id: user.id.toString(),
        username: user.username
      }
    });
  } catch (error) {
    console.error('Set beacon error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Get current beacon user
app.get('/api/beacon/current', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, username FROM users WHERE is_current_beacon = TRUE LIMIT 1'
    );

    if (result.rows.length === 0) {
      return res.json({
        success: true,
        beaconUser: null,
        message: 'No beacon is currently assigned'
      });
    }

    const user = result.rows[0];
    res.json({
      success: true,
      beaconUser: {
        id: user.id.toString(),
        username: user.username
      }
    });
  } catch (error) {
    console.error('Get current beacon error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Check if current user is the beacon (requires auth)
app.get('/api/beacon/status', requireAuth, async (req, res) => {
  try {
    const userId = req.user.userId;

    const result = await pool.query(
      'SELECT is_current_beacon FROM users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({
      success: true,
      isCurrentBeacon: result.rows[0].is_current_beacon || false
    });
  } catch (error) {
    console.error('Get beacon status error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Admin: Clear current beacon (no one can beacon)
app.post('/api/beacon/clear', requireAdmin, async (req, res) => {
  try {
    await pool.query('UPDATE users SET is_current_beacon = FALSE');

    console.log('Beacon cleared - no active beacon');
    res.json({
      success: true,
      message: 'Beacon cleared'
    });
  } catch (error) {
    console.error('Clear beacon error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ============================================
// Image Upload Endpoint
// ============================================

// Admin: Upload an image (stores as base64 data URL)
// Note: For production, consider using cloud storage (S3, Cloudinary, etc.)
app.post('/api/upload/image', requireAdmin, express.raw({ type: 'image/*', limit: '5mb' }), async (req, res) => {
  try {
    if (!req.body || req.body.length === 0) {
      return res.status(400).json({ success: false, message: 'No image data provided' });
    }

    const contentType = req.headers['content-type'] || 'image/png';

    // Validate content type
    const allowedTypes = ['image/png', 'image/jpeg', 'image/jpg', 'image/gif', 'image/webp'];
    if (!allowedTypes.includes(contentType)) {
      return res.status(400).json({ success: false, message: 'Invalid image type. Allowed: PNG, JPEG, GIF, WebP' });
    }

    // Convert to base64 data URL
    const base64 = req.body.toString('base64');
    const imageUrl = `data:${contentType};base64,${base64}`;

    res.json({
      success: true,
      imageUrl
    });
  } catch (error) {
    console.error('Image upload error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Update FCM token for a user (requires authentication)
app.post('/api/users/:userId/fcm-token', requireAuth, async (req, res) => {
  try {
    const { fcmToken } = req.body;
    const userId = sanitizeInt(req.params.userId);
    const authenticatedUserId = req.user.userId;

    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }

    // Security: Users can only update their own FCM token
    if (userId !== authenticatedUserId) {
      return res.status(403).json({ success: false, message: 'Cannot update FCM token for another user' });
    }

    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ success: false, message: 'FCM token is required' });
    }

    // FCM token validation - must be a reasonable length
    if (fcmToken.length > 500) {
      return res.status(400).json({ success: false, message: 'Invalid FCM token format' });
    }

    await pool.query('UPDATE users SET fcm_token = $1 WHERE id = $2', [fcmToken, userId]);

    res.json({ success: true, message: 'FCM token updated' });
  } catch (error) {
    console.error('Update FCM token error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Health check
app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'connected' });
  } catch (error) {
    res.json({ status: 'error', database: 'disconnected' });
  }
});

const PORT = process.env.PORT || 3000;

// Track server instance for graceful shutdown
let server;

// Initialize DB and start server
initDb(pool).then(async () => {
  server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`Karass backend running on http://0.0.0.0:${PORT}`);
    console.log('Access from other devices: http://192.168.5.143:' + PORT);
    console.log('Connected to Neon PostgreSQL database');
  });
}).catch(error => {
  console.error('Failed to initialize database:', error);
  process.exit(1);
});

// Graceful shutdown handler
async function gracefulShutdown(signal) {
  console.log(`\n${signal} received. Shutting down gracefully...`);

  // Stop accepting new connections
  if (server) {
    server.close(() => {
      console.log('HTTP server closed');
    });
  }

  // Close database pool
  try {
    await pool.end();
    console.log('Database pool closed');
  } catch (error) {
    console.error('Error closing database pool:', error.message);
  }

  process.exit(0);
}

// Listen for termination signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
