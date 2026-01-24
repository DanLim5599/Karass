/**
 * Input validation utilities
 */

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

module.exports = {
  isValidEmail,
  isValidUsername,
  isValidPassword,
  sanitizeInt
};
