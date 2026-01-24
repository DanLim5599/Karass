require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const crypto = require('crypto');
const axios = require('axios');

// Import modular utilities and middleware
const { isValidEmail, isValidUsername, isValidPassword, sanitizeInt } = require('./utils/validation');
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
        message: 'Please use Twitter/X to sign in'
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
    const { message, startsAt, expiresAt } = req.body;
    const adminUserId = req.adminId; // Set by requireAdmin middleware

    if (!message || typeof message !== 'string' || message.trim().length === 0) {
      return res.status(400).json({ success: false, message: 'Message is required' });
    }
    if (message.length > 1000) {
      return res.status(400).json({ success: false, message: 'Message too long (max 1000 chars)' });
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
      `INSERT INTO announcements (message, created_by, starts_at, expires_at)
       VALUES ($1, $2, $3, $4)
       RETURNING id, message, created_at, starts_at, expires_at`,
      [sanitizedMessage, adminUserId, startsAtDate, expiresAtDate]
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
        expiresAt: announcement.expires_at
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
      SELECT a.id, a.message, a.created_at, a.starts_at, a.expires_at, u.username as created_by_username
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
        createdBy: row.created_by_username
      }))
    });
  } catch (error) {
    console.error('Get announcements error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// Update FCM token for a user
app.post('/api/users/:userId/fcm-token', async (req, res) => {
  try {
    const { fcmToken } = req.body;
    const userId = sanitizeInt(req.params.userId);

    if (!userId) {
      return res.status(400).json({ success: false, message: 'Invalid user ID' });
    }
    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ success: false, message: 'FCM token is required' });
    }

    // Verify user exists
    const userResult = await pool.query('SELECT id FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
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
  server = app.listen(PORT, () => {
    console.log(`Karass backend running on http://localhost:${PORT}`);
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
