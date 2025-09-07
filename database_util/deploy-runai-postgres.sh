#!/bin/bash

# RunAI Chat PostgreSQL Schema Deployment Script
# This script creates a new PostgreSQL database with OpenWebUI schema
# Usage: ./deploy-runai-postgres.sh <container_name> <username> <password> [database_name] [port]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} RunAI Chat PostgreSQL Deployment${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check arguments
if [ $# -lt 3 ]; then
    print_error "Usage: $0 <container_name> <username> <password> [database_name] [port]"
    echo ""
    echo "Example:"
    echo "  $0 runai-postgres-1 runai_user secure_password123 runai_chat 5432"
    echo "  $0 runai-postgres-2 runai_user secure_password123"
    exit 1
fi

# Parse arguments
CONTAINER_NAME="$1"
DB_USERNAME="$2"
DB_PASSWORD="$3"
DB_NAME="${4:-runai_chat}"
DB_PORT="${5:-5432}"

print_header

print_status "Deployment Configuration:"
echo "  Container Name: $CONTAINER_NAME"
echo "  Username: $DB_USERNAME"
echo "  Database: $DB_NAME"
echo "  Port: $DB_PORT"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Generate dynamic container name if conflicts exist
ORIGINAL_CONTAINER_NAME="$CONTAINER_NAME"
COUNTER=1
while docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; do
    CONTAINER_NAME="${ORIGINAL_CONTAINER_NAME}-${COUNTER}"
    ((COUNTER++))
done

if [ "$CONTAINER_NAME" != "$ORIGINAL_CONTAINER_NAME" ]; then
    print_warning "Container '$ORIGINAL_CONTAINER_NAME' already exists."
    print_status "Using dynamic name: $CONTAINER_NAME"
fi

# Find available port if specified port is in use
ORIGINAL_PORT="$DB_PORT"
while ss -tuln 2>/dev/null | grep -q ":$DB_PORT " || netstat -tuln 2>/dev/null | grep -q ":$DB_PORT "; do
    print_warning "Port $DB_PORT is already in use."
    DB_PORT=$((DB_PORT + 1))
    print_status "Trying port $DB_PORT..."
done

if [ "$DB_PORT" != "$ORIGINAL_PORT" ]; then
    print_status "Using dynamic port: $DB_PORT (original $ORIGINAL_PORT was in use)"
fi

print_status "Creating PostgreSQL container..."

# Create PostgreSQL container
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -e POSTGRES_DB="$DB_NAME" \
    -e POSTGRES_USER="$DB_USERNAME" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -p "$DB_PORT:5432" \
    -v "${CONTAINER_NAME}_data:/var/lib/postgresql/data" \
    postgres:15-alpine

print_status "Waiting for PostgreSQL to start..."
sleep 10

# Wait for PostgreSQL to be ready
for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USERNAME" -d "$DB_NAME" >/dev/null 2>&1; then
        print_status "PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "PostgreSQL failed to start within 30 seconds."
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
    sleep 1
done

print_status "Creating OpenWebUI database schema..."

# Check if schema backup file exists
SCHEMA_FILE="openwebui_schema_backup.sql"
if [ ! -f "$SCHEMA_FILE" ]; then
    print_error "Schema backup file '$SCHEMA_FILE' not found in current directory."
    print_error "Please ensure the schema backup file is present."
    exit 1
fi

# Apply schema
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USERNAME" -d "$DB_NAME" < "$SCHEMA_FILE"

print_status "Schema deployment completed successfully!"

# Test connection
print_status "Testing database connection..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USERNAME" -d "$DB_NAME" -c "SELECT count(*) as tables FROM information_schema.tables WHERE table_schema = 'public';"

print_status "Container Information:"
echo "  Container ID: $(docker ps --format '{{.ID}}' --filter name="$CONTAINER_NAME")"
echo "  Status: $(docker ps --format '{{.Status}}' --filter name="$CONTAINER_NAME")"
echo "  Connection String: postgresql://$DB_USERNAME:$DB_PASSWORD@localhost:$DB_PORT/$DB_NAME"

print_status "Deployment completed! Your RunAI Chat PostgreSQL database is ready."

echo ""
echo "Next steps:"
echo "1. Update your application configuration to use the new database"
echo "2. If you need data, restore from backup using: ./restore-runai-data.sh"
echo "3. Deploy OpenWebUI containers pointing to this database"