const { Pool } = require('pg');
require('dotenv').config();

// Database connection configuration
const dbConfig = {
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT) || 10000,
  idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT) || 30000,
  max: parseInt(process.env.DB_MAX_CONNECTIONS) || 20,
};

console.log('Database Configuration:', {
  host: dbConfig.host,
  port: dbConfig.port,
  database: dbConfig.database,
  user: dbConfig.user,
  ssl: dbConfig.ssl
});

// Create connection pool
const pool = new Pool(dbConfig);

// Handle pool errors
pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Database utility functions
class Database {
  static async query(text, params) {
    const start = Date.now();
    try {
      const res = await pool.query(text, params);
      const duration = Date.now() - start;
      console.log('Database query executed', { text, duration, rows: res.rowCount });
      return res;
    } catch (error) {
      console.error('Database query error:', error);
      throw error;
    }
  }

  static async getClient() {
    return await pool.connect();
  }

  static async testConnection() {
    try {
      const res = await this.query('SELECT NOW() as current_time, version() as pg_version');
      return {
        success: true,
        timestamp: res.rows[0].current_time,
        version: res.rows[0].pg_version
      };
    } catch (error) {
      return {
        success: false,
        error: error.message
      };
    }
  }

  static async initializeSchema() {
    try {
      // Create users table
      await this.query(`
        CREATE TABLE IF NOT EXISTS runaii.users (
          id SERIAL PRIMARY KEY,
          username VARCHAR(255) UNIQUE NOT NULL,
          email VARCHAR(255) UNIQUE NOT NULL,
          password_hash VARCHAR(255) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create chats table
      await this.query(`
        CREATE TABLE IF NOT EXISTS runaii.chats (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES runaii.users(id) ON DELETE CASCADE,
          title VARCHAR(255) NOT NULL DEFAULT 'New Chat',
          model VARCHAR(100) NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create messages table
      await this.query(`
        CREATE TABLE IF NOT EXISTS runaii.messages (
          id SERIAL PRIMARY KEY,
          chat_id INTEGER REFERENCES runaii.chats(id) ON DELETE CASCADE,
          role VARCHAR(50) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
          content TEXT NOT NULL,
          model VARCHAR(100),
          tokens_used INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      // Create API keys table for storing user's AI service keys
      await this.query(`
        CREATE TABLE IF NOT EXISTS runaii.user_api_keys (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES runaii.users(id) ON DELETE CASCADE,
          service VARCHAR(50) NOT NULL CHECK (service IN ('openai', 'anthropic', 'google')),
          api_key_encrypted TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, service)
        )
      `);

      // Create usage tracking table
      await this.query(`
        CREATE TABLE IF NOT EXISTS runaii.usage_stats (
          id SERIAL PRIMARY KEY,
          user_id INTEGER REFERENCES runaii.users(id) ON DELETE CASCADE,
          model VARCHAR(100) NOT NULL,
          tokens_used INTEGER NOT NULL,
          cost_usd DECIMAL(10, 6) DEFAULT 0,
          request_date DATE DEFAULT CURRENT_DATE,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);

      console.log('✅ Database schema initialized successfully');
      return { success: true };
    } catch (error) {
      console.error('❌ Schema initialization error:', error);
      return { success: false, error: error.message };
    }
  }

  static async createUser(username, email, passwordHash) {
    try {
      const result = await this.query(
        'INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email, created_at',
        [username, email, passwordHash]
      );
      return result.rows[0];
    } catch (error) {
      throw error;
    }
  }

  static async createChat(userId, title, model) {
    try {
      const result = await this.query(
        'INSERT INTO chats (user_id, title, model) VALUES ($1, $2, $3) RETURNING *',
        [userId, title, model]
      );
      return result.rows[0];
    } catch (error) {
      throw error;
    }
  }

  static async addMessage(chatId, role, content, model, tokensUsed = 0) {
    try {
      const result = await this.query(
        'INSERT INTO messages (chat_id, role, content, model, tokens_used) VALUES ($1, $2, $3, $4, $5) RETURNING *',
        [chatId, role, content, model, tokensUsed]
      );
      return result.rows[0];
    } catch (error) {
      throw error;
    }
  }

  static async getChatHistory(chatId, limit = 50) {
    try {
      const result = await this.query(
        'SELECT * FROM messages WHERE chat_id = $1 ORDER BY created_at ASC LIMIT $2',
        [chatId, limit]
      );
      return result.rows;
    } catch (error) {
      throw error;
    }
  }

  static async getUserChats(userId, limit = 20) {
    try {
      const result = await this.query(
        'SELECT * FROM chats WHERE user_id = $1 ORDER BY updated_at DESC LIMIT $2',
        [userId, limit]
      );
      return result.rows;
    } catch (error) {
      throw error;
    }
  }

  static async close() {
    await pool.end();
  }
}

module.exports = Database;