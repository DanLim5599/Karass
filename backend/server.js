require('dotenv').config();
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const { google } = require('googleapis');
const jwt = require('jsonwebtoken');
const axios = require('axios');

const app = express();

// Security constants
const BCRYPT_ROUNDS = 12;
const RATE_LIMIT_MAX_IPS = 10000; // Maximum IPs to track (prevents memory exhaustion)

// Validate required environment variables at startup
function validateEnv() {
  const required = ['DATABASE_URL'];
  const missing = required.filter(key => !process.env[key]);
  if (missing.length > 0) {
    console.error(`FATAL: Missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }

  // Warn about insecure defaults
  if (!process.env.ADMIN_SECRET_KEY) {
    console.error('FATAL: ADMIN_SECRET_KEY environment variable is required');
    process.exit(1);
  }
  if (process.env.ADMIN_PASSWORD === 'testpass' || !process.env.ADMIN_PASSWORD) {
    console.warn('WARNING: Using weak admin password. Set a strong ADMIN_PASSWORD for production.');
  }
}

validateEnv();

// JWT Configuration
const JWT_SECRET = process.env.JWT_SECRET || 'fallback-secret-change-in-production';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

// Twitter OAuth Configuration
const TWITTER_CLIENT_ID = process.env.TWITTER_CLIENT_ID;
const TWITTER_CLIENT_SECRET = process.env.TWITTER_CLIENT_SECRET;
const TWITTER_CALLBACK_URL = 'karass://callback';

// In-memory store for PKCE verifiers (use Redis in production)
const pkceStore = new Map();
const PKCE_TTL = 10 * 60 * 1000; // 10 minutes

// Clean up expired PKCE entries
setInterval(() => {
  const now = Date.now();
  for (const [state, data] of pkceStore.entries()) {
    if (now - data.createdAt > PKCE_TTL) {
      pkceStore.delete(state);
    }
  }
}, 60000); // Clean every minute

// Generate JWT token for a user
function generateToken(user) {
  return jwt.sign(
    {
      userId: user.id,
      username: user.username,
      isAdmin: user.is_admin
    },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

// Middleware to verify JWT token
function requireAuth(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) {
    return res.status(401).json({ success: false, message: 'Authentication required' });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, message: 'Token expired' });
    }
    return res.status(401).json({ success: false, message: 'Invalid token' });
  }
}

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

// Security: Limit request body size to prevent DoS
app.use(express.json({ limit: '10kb' }));

// Simple in-memory rate limiting with memory management
const rateLimitMap = new Map();
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 100; // max requests per window

// Periodically clean up old rate limit entries to prevent memory leaks
setInterval(() => {
  const now = Date.now();
  const windowStart = now - RATE_LIMIT_WINDOW;
  for (const [ip, requests] of rateLimitMap.entries()) {
    const validRequests = requests.filter(time => time > windowStart);
    if (validRequests.length === 0) {
      rateLimitMap.delete(ip);
    } else {
      rateLimitMap.set(ip, validRequests);
    }
  }
}, RATE_LIMIT_WINDOW);

function rateLimit(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress;
  const now = Date.now();
  const windowStart = now - RATE_LIMIT_WINDOW;

  // Prevent memory exhaustion from too many unique IPs
  if (rateLimitMap.size >= RATE_LIMIT_MAX_IPS && !rateLimitMap.has(ip)) {
    return res.status(429).json({ success: false, message: 'Too many requests' });
  }

  if (!rateLimitMap.has(ip)) {
    rateLimitMap.set(ip, []);
  }

  const requests = rateLimitMap.get(ip).filter(time => time > windowStart);
  requests.push(now);
  rateLimitMap.set(ip, requests);

  if (requests.length > RATE_LIMIT_MAX) {
    return res.status(429).json({ success: false, message: 'Too many requests' });
  }

  next();
}

app.use(rateLimit);

// Input validation helpers
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

function isValidUsername(username) {
  // 3-30 chars, alphanumeric and underscores only
  const usernameRegex = /^[a-zA-Z0-9_]{3,30}$/;
  return usernameRegex.test(username);
}

function isValidPassword(password) {
  // Minimum 8 characters with at least one uppercase, one lowercase, and one number
  if (typeof password !== 'string' || password.length < 8) {
    return false;
  }
  const hasUppercase = /[A-Z]/.test(password);
  const hasLowercase = /[a-z]/.test(password);
  const hasNumber = /[0-9]/.test(password);
  return hasUppercase && hasLowercase && hasNumber;
}

function sanitizeInt(value) {
  const num = parseInt(value, 10);
  return Number.isNaN(num) ? null : num;
}

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

// Firebase Cloud Messaging configuration
const FCM_PROJECT_ID = 'karass-b41bc';
const SERVICE_ACCOUNT_PATH = path.join(__dirname, 'service-account.json');

// Get OAuth2 access token for FCM
async function getAccessToken() {
  if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
    console.log('Warning: service-account.json not found. Push notifications disabled.');
    return null;
  }

  const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  const jwtClient = new google.auth.JWT(
    serviceAccount.client_email,
    null,
    serviceAccount.private_key,
    ['https://www.googleapis.com/auth/firebase.messaging']
  );

  const tokens = await jwtClient.authorize();
  return tokens.access_token;
}

// Send FCM push notification to a topic
async function sendPushToTopic(topic, title, body, data = {}) {
  const accessToken = await getAccessToken();
  if (!accessToken) return false;

  const message = {
    message: {
      topic: topic,
      notification: {
        title: title,
        body: body
      },
      data: {
        ...data,
        type: 'announcement'
      },
      android: {
        priority: 'high',
        notification: {
          channel_id: 'announcement_channel'
        }
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title: title,
              body: body
            },
            sound: 'default'
          }
        }
      }
    }
  };

  return new Promise((resolve) => {
    const postData = JSON.stringify(message);

    const options = {
      hostname: 'fcm.googleapis.com',
      port: 443,
      path: `/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          console.log('Push notification sent successfully');
          resolve(true);
        } else {
          console.log('FCM response:', res.statusCode, data);
          resolve(false);
        }
      });
    });

    req.on('error', (e) => {
      console.error('FCM error:', e.message);
      resolve(false);
    });

    req.write(postData);
    req.end();
  });
}

// Helper function to check if a column exists
async function columnExists(tableName, columnName) {
  const result = await pool.query(`
    SELECT column_name FROM information_schema.columns
    WHERE table_name = $1 AND column_name = $2
  `, [tableName, columnName]);
  return result.rows.length > 0;
}

// Helper function to add a column if it doesn't exist
async function addColumnIfNotExists(tableName, columnName, columnDef) {
  if (!(await columnExists(tableName, columnName))) {
    await pool.query(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDef}`);
    console.log(`Added column ${columnName} to ${tableName}`);
  }
}

// Initialize database tables
async function initDb() {
  try {
    // Create users table (base schema for new databases)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email TEXT UNIQUE,
        username TEXT UNIQUE NOT NULL,
        password TEXT,
        twitter_handle TEXT,
        twitter_id TEXT UNIQUE,
        auth_provider TEXT DEFAULT 'email',
        fcm_token TEXT,
        is_approved BOOLEAN DEFAULT TRUE,
        is_admin BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Create announcements table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS announcements (
        id SERIAL PRIMARY KEY,
        message TEXT NOT NULL,
        created_by INTEGER REFERENCES users(id),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        starts_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP
      )
    `);

    // Migration: Add new columns for existing databases
    await addColumnIfNotExists('announcements', 'starts_at', 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
    await addColumnIfNotExists('announcements', 'expires_at', 'TIMESTAMP');

    // Migration: Add new columns for existing databases
    await addColumnIfNotExists('users', 'twitter_id', 'TEXT UNIQUE');
    await addColumnIfNotExists('users', 'auth_provider', "TEXT DEFAULT 'email'");

    // Note: Making email/password nullable requires dropping NOT NULL constraint
    // This is handled by the table definition above for new databases
    // For existing databases, run these SQL commands manually if needed:
    // ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
    // ALTER TABLE users ALTER COLUMN password DROP NOT NULL;

    console.log('Database tables initialized');
  } catch (error) {
    console.error('Database initialization error:', error);
    throw error;
  }
}

// Create Account
app.post('/api/auth/register', async (req, res) => {
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

    // Auto-admin for specific email
    const isAdmin = email.toLowerCase() === 'davidlimusername@gmail.com';

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
app.post('/api/auth/login', async (req, res) => {
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
app.get('/api/auth/twitter/init', async (req, res) => {
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
app.post('/api/auth/twitter/callback', async (req, res) => {
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

    // Validate state (optional - can verify against stored state)
    const storedData = pkceStore.get(state);
    if (storedData) {
      pkceStore.delete(state); // Clean up
    }

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

// Admin secret key for API authentication (required - no fallback)
const ADMIN_SECRET_KEY = process.env.ADMIN_SECRET_KEY;

// Middleware to verify admin access
// Requires both: valid admin user ID AND correct admin secret key
async function requireAdmin(req, res, next) {
  try {
    // Check for admin secret key in Authorization header
    const authHeader = req.headers['authorization'];
    const providedKey = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!providedKey || providedKey !== ADMIN_SECRET_KEY) {
      return res.status(401).json({ success: false, message: 'Invalid admin credentials' });
    }

    const adminId = sanitizeInt(req.body.adminId || req.headers['x-admin-id']);
    if (!adminId) {
      return res.status(401).json({ success: false, message: 'Admin ID required' });
    }

    const result = await pool.query('SELECT is_admin FROM users WHERE id = $1', [adminId]);
    if (result.rows.length === 0 || !result.rows[0].is_admin) {
      return res.status(403).json({ success: false, message: 'Admin access required' });
    }

    req.adminId = adminId;
    next();
  } catch (error) {
    console.error('Admin verification error:', error.message);
    return res.status(500).json({ success: false, message: 'Server error' });
  }
}

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

// Create announcement (admin only)
app.post('/api/announcements', async (req, res) => {
  try {
    const { userId, message, startsAt, expiresAt } = req.body;

    const userIdNum = sanitizeInt(userId);
    if (!userIdNum) {
      return res.status(400).json({ success: false, message: 'Valid userId is required' });
    }
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

    // Check if user is admin
    const userResult = await pool.query('SELECT is_admin FROM users WHERE id = $1', [userIdNum]);

    if (userResult.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    if (!userResult.rows[0].is_admin) {
      return res.status(403).json({ success: false, message: 'Admin access required' });
    }

    // Delete all existing announcements (only keep one at a time)
    await pool.query('DELETE FROM announcements');

    // Create announcement (sanitize message)
    const sanitizedMessage = message.trim();
    const result = await pool.query(
      `INSERT INTO announcements (message, created_by, starts_at, expires_at)
       VALUES ($1, $2, $3, $4)
       RETURNING id, message, created_at, starts_at, expires_at`,
      [sanitizedMessage, userIdNum, startsAtDate, expiresAtDate]
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
initDb().then(async () => {
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
