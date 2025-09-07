#!/bin/bash

# RunAI Chat Data Restoration Script
# This script restores data to an existing PostgreSQL database
# Usage: ./restore-runai-data.sh <container_name> <username> <database_name>

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
    echo -e "${BLUE} RunAI Chat Data Restoration${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check arguments
if [ $# -lt 3 ]; then
    print_error "Usage: $0 <container_name> <username> <database_name>"
    echo ""
    echo "Example:"
    echo "  $0 runai-postgres-1 runai_user runai_chat"
    exit 1
fi

# Parse arguments
CONTAINER_NAME="$1"
DB_USERNAME="$2"
DB_NAME="$3"

print_header

print_status "Restoration Configuration:"
echo "  Container Name: $CONTAINER_NAME"
echo "  Username: $DB_USERNAME"
echo "  Database: $DB_NAME"
echo ""

# Check if container exists and is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_error "Container '$CONTAINER_NAME' is not running."
    exit 1
fi

# Check if data backup file exists
DATA_FILE="openwebui_data_backup.sql"
if [ ! -f "$DATA_FILE" ]; then
    print_error "Data backup file '$DATA_FILE' not found in current directory."
    exit 1
fi

print_warning "This will replace all existing data in the database."
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    print_error "Restoration cancelled."
    exit 1
fi

print_status "Clearing existing data..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USERNAME" -d "$DB_NAME" -c "
    TRUNCATE TABLE \"user\", \"chat\", \"auth\", \"model\", \"function\", \"tag\", 
                   \"file\", \"config\", \"feedback\", \"document\", \"prompt\", 
                   \"folder\", \"knowledge\", \"memory\", \"note\", \"tool\", 
                   \"group\", \"channel\", \"channel_member\", \"message\", 
                   \"message_reaction\", \"chatidtag\" RESTART IDENTITY CASCADE;
"

print_status "Restoring data from backup..."
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USERNAME" -d "$DB_NAME" < "$DATA_FILE"

print_status "Verifying restored data..."
docker exec "$CONTAINER_NAME" psql -U "$DB_USERNAME" -d "$DB_NAME" -c "
    SELECT 'users' as table_name, COUNT(*) as records FROM \"user\"
    UNION ALL
    SELECT 'chats' as table_name, COUNT(*) as records FROM \"chat\"
    UNION ALL
    SELECT 'models' as table_name, COUNT(*) as records FROM \"model\"
    UNION ALL
    SELECT 'functions' as table_name, COUNT(*) as records FROM \"function\"
    UNION ALL
    SELECT 'tags' as table_name, COUNT(*) as records FROM \"tag\";
"

print_status "Data restoration completed successfully!"