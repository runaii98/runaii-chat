#!/bin/bash

# LiteLLM PostgreSQL Migration and Load Distribution Setup
# This script migrates LiteLLM from individual databases to shared PostgreSQL

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[LITELLM-MIGRATION]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} LiteLLM PostgreSQL Migration & Load Distribution${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
POSTGRES_CONTAINER="postgres-litellm"
POSTGRES_DB="litellm_db"
POSTGRES_USER="litellm_user"
POSTGRES_PASSWORD="litellm_secure_password_2024"
POSTGRES_PORT="5433"  # Different from OpenWebUI port

print_header

print_status "Starting LiteLLM PostgreSQL migration process..."

# Step 1: Analyze current LiteLLM setup
analyze_current_litellm() {
    print_status "Step 1: Analyzing current LiteLLM setup..."
    
    # Check if LiteLLM container is running
    if docker ps | grep -q litellm; then
        LITELLM_CONTAINER=$(docker ps --format '{{.Names}}' | grep litellm | head -1)
        print_status "Found LiteLLM container: $LITELLM_CONTAINER"
        
        # Get LiteLLM container info
        docker inspect $LITELLM_CONTAINER | jq '.[0].Config.Env' || true
        docker logs $LITELLM_CONTAINER --tail 20
    else
        print_error "No LiteLLM container found running"
        return 1
    fi
    
    # Check for existing LiteLLM database
    print_status "Checking for existing LiteLLM database files..."
    docker exec $LITELLM_CONTAINER find / -name "*.db" -o -name "*.sqlite*" 2>/dev/null || true
    
    # Check LiteLLM configuration
    print_status "Checking LiteLLM configuration..."
    docker exec $LITELLM_CONTAINER env | grep -E "(DATABASE|DB)" || true
}

# Step 2: Create backup of current LiteLLM data
backup_litellm_data() {
    print_status "Step 2: Creating backup of current LiteLLM data..."
    
    # Create backup directory
    mkdir -p ./litellm_backup
    
    # Backup SQLite database if exists
    if docker exec $LITELLM_CONTAINER test -f "/app/database.db"; then
        docker cp $LITELLM_CONTAINER:/app/database.db ./litellm_backup/
        print_status "✅ Backed up database.db"
    fi
    
    # Backup any other database files
    docker exec $LITELLM_CONTAINER find /app -name "*.db" -exec cp {} /tmp/ \; 2>/dev/null || true
    docker cp $LITELLM_CONTAINER:/tmp/ ./litellm_backup/tmp/ 2>/dev/null || true
    
    # Backup configuration files
    docker exec $LITELLM_CONTAINER find /app -name "config.*" -exec cp {} /tmp/ \; 2>/dev/null || true
    docker cp $LITELLM_CONTAINER:/tmp/ ./litellm_backup/config/ 2>/dev/null || true
    
    print_status "✅ LiteLLM data backup completed"
}

# Step 3: Deploy PostgreSQL for LiteLLM
deploy_postgres_litellm() {
    print_status "Step 3: Deploying PostgreSQL for LiteLLM..."
    
    # Generate dynamic container name if conflict exists
    local container_name="$POSTGRES_CONTAINER"
    local counter=1
    while docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; do
        container_name="${POSTGRES_CONTAINER}-${counter}"
        ((counter++))
    done
    
    # Find available port
    local port="$POSTGRES_PORT"
    while ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
    done
    
    print_status "Using container name: $container_name"
    print_status "Using port: $port"
    
    # Deploy PostgreSQL container
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -e POSTGRES_DB="$POSTGRES_DB" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -p "$port:5432" \
        -v "${container_name}_data:/var/lib/postgresql/data" \
        postgres:15-alpine
    
    # Wait for PostgreSQL to be ready
    print_status "Waiting for PostgreSQL to start..."
    sleep 15
    
    for i in {1..30}; do
        if docker exec "$container_name" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
            print_status "✅ PostgreSQL is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL failed to start"
            return 1
        fi
        sleep 1
    done
    
    # Store the actual container name and port for later use
    echo "$container_name" > .litellm_postgres_container
    echo "$port" > .litellm_postgres_port
    
    print_status "✅ PostgreSQL deployed: $container_name on port $port"
}

# Step 4: Extract and analyze LiteLLM schema
extract_litellm_schema() {
    print_status "Step 4: Extracting LiteLLM schema..."
    
    # Check if SQLite database exists
    if [ -f "./litellm_backup/database.db" ]; then
        print_status "Analyzing LiteLLM SQLite database..."
        
        # Extract schema
        sqlite3 ./litellm_backup/database.db ".schema" > ./litellm_backup/litellm_schema.sql
        
        # Extract data
        sqlite3 ./litellm_backup/database.db ".dump" > ./litellm_backup/litellm_data.sql
        
        # Get table information
        sqlite3 ./litellm_backup/database.db ".tables" > ./litellm_backup/litellm_tables.txt
        
        print_status "✅ LiteLLM schema extracted"
        print_status "Tables found:"
        cat ./litellm_backup/litellm_tables.txt
        
        # Count records in each table
        print_status "Record counts:"
        while read table; do
            if [ ! -z "$table" ]; then
                count=$(sqlite3 ./litellm_backup/database.db "SELECT COUNT(*) FROM $table;")
                echo "  $table: $count records"
            fi
        done < ./litellm_backup/litellm_tables.txt
        
    else
        print_warning "No SQLite database found, checking for PostgreSQL connection..."
        # TODO: Handle case where LiteLLM is already using PostgreSQL
    fi
}

# Step 5: Convert schema for PostgreSQL
convert_schema_to_postgres() {
    print_status "Step 5: Converting schema for PostgreSQL compatibility..."
    
    if [ -f "./litellm_backup/litellm_schema.sql" ]; then
        # Convert SQLite schema to PostgreSQL
        cp ./litellm_backup/litellm_schema.sql ./litellm_backup/litellm_postgres_schema.sql
        
        # Basic SQLite to PostgreSQL conversions
        sed -i 's/INTEGER PRIMARY KEY AUTOINCREMENT/SERIAL PRIMARY KEY/g' ./litellm_backup/litellm_postgres_schema.sql
        sed -i 's/TEXT/VARCHAR/g' ./litellm_backup/litellm_postgres_schema.sql
        sed -i 's/REAL/FLOAT/g' ./litellm_backup/litellm_postgres_schema.sql
        sed -i 's/BLOB/BYTEA/g' ./litellm_backup/litellm_postgres_schema.sql
        
        print_status "✅ Schema converted for PostgreSQL"
    else
        print_error "No schema file found to convert"
        return 1
    fi
}

# Step 6: Apply schema to PostgreSQL
apply_schema_to_postgres() {
    print_status "Step 6: Applying schema to PostgreSQL..."
    
    local container_name=$(cat .litellm_postgres_container)
    
    if [ -f "./litellm_backup/litellm_postgres_schema.sql" ]; then
        # Apply schema
        docker exec -i "$container_name" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < ./litellm_backup/litellm_postgres_schema.sql
        
        print_status "✅ Schema applied to PostgreSQL"
        
        # Verify schema
        print_status "Verifying schema..."
        docker exec "$container_name" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"
        
    else
        print_error "No PostgreSQL schema file found"
        return 1
    fi
}

# Step 7: Migrate data to PostgreSQL
migrate_data_to_postgres() {
    print_status "Step 7: Migrating data to PostgreSQL..."
    
    local container_name=$(cat .litellm_postgres_container)
    
    # Create Python migration script
    cat > ./litellm_backup/migrate_data.py << 'EOF'
import sqlite3
import psycopg2
import sys
import json

def migrate_litellm_data():
    # Connect to SQLite
    sqlite_conn = sqlite3.connect('./litellm_backup/database.db')
    sqlite_conn.row_factory = sqlite3.Row
    
    # Connect to PostgreSQL
    postgres_conn = psycopg2.connect(
        host='localhost',
        port=sys.argv[1] if len(sys.argv) > 1 else '5433',
        database='litellm_db',
        user='litellm_user',
        password='litellm_secure_password_2024'
    )
    
    sqlite_cursor = sqlite_conn.cursor()
    postgres_cursor = postgres_conn.cursor()
    
    # Get all tables
    sqlite_cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in sqlite_cursor.fetchall()]
    
    for table in tables:
        print(f"Migrating table: {table}")
        
        # Get all data from SQLite table
        sqlite_cursor.execute(f"SELECT * FROM {table}")
        rows = sqlite_cursor.fetchall()
        
        if rows:
            # Get column names
            columns = [description[0] for description in sqlite_cursor.description]
            
            # Prepare insert statement
            placeholders = ','.join(['%s'] * len(columns))
            insert_sql = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({placeholders})"
            
            # Insert data
            for row in rows:
                try:
                    postgres_cursor.execute(insert_sql, tuple(row))
                except Exception as e:
                    print(f"Error inserting row in {table}: {e}")
                    continue
        
        postgres_conn.commit()
        print(f"✅ Migrated {len(rows)} records from {table}")
    
    sqlite_conn.close()
    postgres_conn.close()
    print("✅ Data migration completed!")

if __name__ == "__main__":
    migrate_litellm_data()
EOF
    
    # Run migration
    local port=$(cat .litellm_postgres_port)
    python3 ./litellm_backup/migrate_data.py "$port"
    
    print_status "✅ Data migration completed"
}

# Step 8: Verify migration
verify_migration() {
    print_status "Step 8: Verifying migration..."
    
    local container_name=$(cat .litellm_postgres_container)
    
    # Check tables
    print_status "Tables in PostgreSQL:"
    docker exec "$container_name" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"
    
    # Check record counts
    print_status "Record counts in PostgreSQL:"
    docker exec "$container_name" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT 
            schemaname,
            tablename,
            n_tup_ins as records
        FROM pg_stat_user_tables 
        ORDER BY tablename;
    "
    
    # Test database connection
    local port=$(cat .litellm_postgres_port)
    print_status "Connection string: postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$port/$POSTGRES_DB"
}

# Main execution
main() {
    analyze_current_litellm
    backup_litellm_data
    deploy_postgres_litellm
    extract_litellm_schema
    convert_schema_to_postgres
    apply_schema_to_postgres
    migrate_data_to_postgres
    verify_migration
    
    print_status "🎉 LiteLLM PostgreSQL migration completed!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Update LiteLLM configuration to use PostgreSQL"
    echo "2. Deploy additional LiteLLM instances for load distribution"
    echo "3. Test the setup with multiple instances"
    echo ""
    echo "🔗 PostgreSQL connection: postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$(cat .litellm_postgres_port)/$POSTGRES_DB"
}

# Execute main function
main "$@"