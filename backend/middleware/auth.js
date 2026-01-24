/**
 * Authentication middleware
 */

const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET;

/**
 * Middleware to verify JWT token
 */
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

/**
 * Middleware to verify admin access using JWT
 * @param {Object} pool - Database connection pool
 */
function createRequireAdmin(pool) {
  return async function requireAdmin(req, res, next) {
    try {
      // First verify JWT token
      const authHeader = req.headers['authorization'];
      const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

      if (!token) {
        return res.status(401).json({ success: false, message: 'Authentication required' });
      }

      let decoded;
      try {
        decoded = jwt.verify(token, JWT_SECRET);
      } catch (error) {
        if (error.name === 'TokenExpiredError') {
          return res.status(401).json({ success: false, message: 'Token expired' });
        }
        return res.status(401).json({ success: false, message: 'Invalid token' });
      }

      // Verify user is still admin in database (in case privileges were revoked)
      const result = await pool.query('SELECT is_admin FROM users WHERE id = $1', [decoded.userId]);
      if (result.rows.length === 0 || !result.rows[0].is_admin) {
        return res.status(403).json({ success: false, message: 'Admin access required' });
      }

      req.user = decoded;
      req.adminId = decoded.userId;
      next();
    } catch (error) {
      console.error('Admin verification error:', error.message);
      return res.status(500).json({ success: false, message: 'Server error' });
    }
  };
}

/**
 * Generate JWT token for a user
 */
function generateToken(user) {
  const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';
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

module.exports = {
  requireAuth,
  createRequireAdmin,
  generateToken
};
