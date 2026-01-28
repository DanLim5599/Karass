/**
 * Database utilities and schema management
 */

// Allowed table and column names (whitelist for SQL injection prevention)
const ALLOWED_TABLES = ['users', 'announcements'];
const ALLOWED_IDENTIFIER_PATTERN = /^[a-z_][a-z0-9_]*$/;

/**
 * Validate that an identifier (table/column name) is safe to use in SQL
 * Prevents SQL injection by only allowing alphanumeric and underscore characters
 */
function validateIdentifier(name, type = 'identifier') {
  if (!name || typeof name !== 'string') {
    throw new Error(`Invalid ${type}: must be a non-empty string`);
  }
  if (!ALLOWED_IDENTIFIER_PATTERN.test(name)) {
    throw new Error(`Invalid ${type} "${name}": only lowercase letters, numbers, and underscores allowed`);
  }
  if (name.length > 63) {
    throw new Error(`Invalid ${type} "${name}": exceeds maximum length of 63 characters`);
  }
  return name;
}

/**
 * Validate table name against whitelist
 */
function validateTableName(tableName) {
  validateIdentifier(tableName, 'table name');
  if (!ALLOWED_TABLES.includes(tableName)) {
    throw new Error(`Table "${tableName}" is not in the allowed tables list`);
  }
  return tableName;
}

/**
 * Check if a column exists in a table
 */
async function columnExists(pool, tableName, columnName) {
  // Validate inputs (parameterized query handles the actual values safely)
  validateTableName(tableName);
  validateIdentifier(columnName, 'column name');

  const result = await pool.query(`
    SELECT column_name FROM information_schema.columns
    WHERE table_name = $1 AND column_name = $2
  `, [tableName, columnName]);
  return result.rows.length > 0;
}

/**
 * Add a column if it doesn't exist
 * Note: PostgreSQL doesn't support parameterized DDL statements for identifiers,
 * so we validate inputs strictly before interpolation
 */
async function addColumnIfNotExists(pool, tableName, columnName, columnDef) {
  // Validate table and column names
  validateTableName(tableName);
  validateIdentifier(columnName, 'column name');

  // Validate column definition (basic check - only allow specific patterns)
  if (!columnDef || typeof columnDef !== 'string') {
    throw new Error('Invalid column definition');
  }

  if (!(await columnExists(pool, tableName, columnName))) {
    // Safe to interpolate after validation
    await pool.query(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnDef}`);
    console.log(`Added column ${columnName} to ${tableName}`);
  }
}

/**
 * Initialize database tables
 */
async function initDb(pool) {
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
    await addColumnIfNotExists(pool, 'announcements', 'starts_at', 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP');
    await addColumnIfNotExists(pool, 'announcements', 'expires_at', 'TIMESTAMP');
    await addColumnIfNotExists(pool, 'users', 'twitter_id', 'TEXT UNIQUE');
    await addColumnIfNotExists(pool, 'users', 'auth_provider', "TEXT DEFAULT 'email'");
    await addColumnIfNotExists(pool, 'users', 'github_id', 'TEXT UNIQUE');
    await addColumnIfNotExists(pool, 'users', 'github_handle', 'TEXT');

    // Migration: Drop NOT NULL constraints for Twitter OAuth support
    try {
      await pool.query('ALTER TABLE users ALTER COLUMN email DROP NOT NULL');
      console.log('Dropped NOT NULL constraint on email column');
    } catch (e) {
      if (!e.message.includes('does not exist') && !e.message.includes('not nullable')) {
        console.log('Note: email column already allows NULL or constraint does not exist');
      }
    }

    try {
      await pool.query('ALTER TABLE users ALTER COLUMN password DROP NOT NULL');
      console.log('Dropped NOT NULL constraint on password column');
    } catch (e) {
      if (!e.message.includes('does not exist') && !e.message.includes('not nullable')) {
        console.log('Note: password column already allows NULL or constraint does not exist');
      }
    }

    // Create indexes for query performance
    await createIndexIfNotExists(pool, 'idx_users_email', 'users', 'email');
    await createIndexIfNotExists(pool, 'idx_users_username', 'users', 'username');
    await createIndexIfNotExists(pool, 'idx_users_twitter_id', 'users', 'twitter_id');
    await createIndexIfNotExists(pool, 'idx_users_github_id', 'users', 'github_id');
    await createIndexIfNotExists(pool, 'idx_announcements_created_at', 'announcements', 'created_at');
    await createIndexIfNotExists(pool, 'idx_announcements_starts_at', 'announcements', 'starts_at');
    await createIndexIfNotExists(pool, 'idx_announcements_expires_at', 'announcements', 'expires_at');

    console.log('Database tables initialized');
  } catch (error) {
    console.error('Database initialization error:', error);
    throw error;
  }
}

/**
 * Create an index if it doesn't exist
 */
async function createIndexIfNotExists(pool, indexName, tableName, columnName) {
  validateIdentifier(indexName, 'index name');
  validateTableName(tableName);
  validateIdentifier(columnName, 'column name');

  try {
    // Check if index exists
    const result = await pool.query(`
      SELECT 1 FROM pg_indexes WHERE indexname = $1
    `, [indexName]);

    if (result.rows.length === 0) {
      await pool.query(`CREATE INDEX ${indexName} ON ${tableName} (${columnName})`);
      console.log(`Created index ${indexName} on ${tableName}(${columnName})`);
    }
  } catch (e) {
    // Index might already exist or column might not exist yet
    console.log(`Note: Could not create index ${indexName}: ${e.message}`);
  }
}

module.exports = {
  columnExists,
  addColumnIfNotExists,
  createIndexIfNotExists,
  validateIdentifier,
  validateTableName,
  initDb
};
