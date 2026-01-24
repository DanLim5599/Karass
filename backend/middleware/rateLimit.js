/**
 * Rate limiting middleware
 */

// Security constants
const RATE_LIMIT_MAX_IPS = 10000;
const RATE_LIMIT_WINDOW = 60000; // 1 minute
const RATE_LIMIT_MAX = 100; // max requests per window
const AUTH_RATE_LIMIT_WINDOW = 900000; // 15 minutes
const AUTH_RATE_LIMIT_MAX = 10; // max auth attempts per 15 minutes

// In-memory stores
const rateLimitMap = new Map();
const authRateLimitMap = new Map();

// Cleanup interval
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
  // Clean up auth rate limit map
  const authWindowStart = now - AUTH_RATE_LIMIT_WINDOW;
  for (const [ip, requests] of authRateLimitMap.entries()) {
    const validRequests = requests.filter(time => time > authWindowStart);
    if (validRequests.length === 0) {
      authRateLimitMap.delete(ip);
    } else {
      authRateLimitMap.set(ip, validRequests);
    }
  }
}, RATE_LIMIT_WINDOW);

/**
 * General rate limiting middleware
 */
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

/**
 * Stricter rate limiting for authentication endpoints
 */
function authRateLimit(req, res, next) {
  const ip = req.ip || req.connection.remoteAddress;
  const now = Date.now();
  const windowStart = now - AUTH_RATE_LIMIT_WINDOW;

  if (!authRateLimitMap.has(ip)) {
    authRateLimitMap.set(ip, []);
  }

  const requests = authRateLimitMap.get(ip).filter(time => time > windowStart);
  requests.push(now);
  authRateLimitMap.set(ip, requests);

  if (requests.length > AUTH_RATE_LIMIT_MAX) {
    const retryAfter = Math.ceil((AUTH_RATE_LIMIT_WINDOW - (now - requests[0])) / 1000);
    res.setHeader('Retry-After', retryAfter);
    return res.status(429).json({
      success: false,
      message: 'Too many authentication attempts. Please try again later.',
      retryAfter: retryAfter
    });
  }

  next();
}

module.exports = {
  rateLimit,
  authRateLimit
};
