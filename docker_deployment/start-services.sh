#!/bin/bash

# Start services script for RunAI Chat all-in-one container

set -e

echo "Starting RunAI Chat All-in-One Container..."

# Initialize PostgreSQL if not already done
if [ ! -f /var/lib/postgresql/14/main/PG_VERSION ]; then
    echo "Initializing PostgreSQL..."
    su - postgres -c "/usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/main"
    
    # Start PostgreSQL temporarily to create user and database
    su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main -l /var/log/postgresql/postgresql.log start"
    sleep 5
    
    # Create user and database
    su - postgres -c "psql --command \"CREATE USER runai_user WITH SUPERUSER PASSWORD 'runai_secure_password';\""
    su - postgres -c "createdb -O runai_user runai_chat"
    
    # Import schema and data
    if [ -f /tmp/schema.sql ]; then
        echo "Importing schema..."
        su - postgres -c "psql -d runai_chat -f /tmp/schema.sql"
    fi
    
    if [ -f /tmp/data.sql ]; then
        echo "Importing data..."
        su - postgres -c "psql -d runai_chat -f /tmp/data.sql"
    fi
    
    # Stop PostgreSQL
    su - postgres -c "/usr/lib/postgresql/14/bin/pg_ctl -D /var/lib/postgresql/14/main stop"
fi

echo "Starting services with supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf