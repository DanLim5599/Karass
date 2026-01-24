/**
 * Database utilities and schema management
 */

/**
 * Check if a column exists in a table
 */
async function columnExists(pool, tableName, columnName) {
  const result = await pool.query(`
    SELECT column_name FROM information_schema.columns
    WHERE table_name = $1 AND column_name = $2
  `, [tableName, columnName]);
  return result.rows.length > 0;
}

/**
 * Add a column if it doesn't exist
 */
async function addColumnIfNotExists(pool, tableName, columnName, columnDef) {
  if (!(await columnExists(pool, tableName, columnName))) {
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

    console.log('Database tables initialized');
  } catch (error) {
    console.error('Database initialization error:', error);
    throw error;
  }
}

module.exports = {
  columnExists,
  addColumnIfNotExists,
  initDb
};
