#!/bin/bash
# Custom initialization script for RunAI Chat PostgreSQL

set -e

# Create additional database if needed
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create extensions if needed
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
    
    -- Create indexes for better performance
    CREATE INDEX IF NOT EXISTS idx_user_email ON "user"(email);
    CREATE INDEX IF NOT EXISTS idx_chat_user_id ON "chat"(user_id);
    CREATE INDEX IF NOT EXISTS idx_message_chat_id ON "message"(chat_id);
    CREATE INDEX IF NOT EXISTS idx_auth_email ON "auth"(email);
    
    -- Grant necessary permissions
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $POSTGRES_USER;
    
    -- Log successful initialization
    SELECT 'RunAI Chat PostgreSQL database initialized successfully!' as status;
EOSQL

echo "RunAI Chat PostgreSQL initialization completed!"