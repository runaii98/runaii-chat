#!/bin/bash

# RunAI Chat Dynamic OpenWebUI Instance Deployment Script
# This script deploys additional OpenWebUI instances with automatic conflict resolution

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[DYNAMIC]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Auto-detect PostgreSQL connection details
get_postgres_connection() {
    local postgres_container="$1"
    
    # Get database environment from container
    local db_user=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_USER=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    local db_password=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_PASSWORD=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    local db_name=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_DB=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    
    # Default values if not found
    db_user=${db_user:-runai_user}
    db_password=${db_password:-runai_secure_password}
    db_name=${db_name:-runai_chat}
    
    # Get network information
    local network=$(docker inspect "$postgres_container" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
    
    if [ "$network" = "bridge" ] || [ -z "$network" ]; then
        # Use host networking
        local postgres_port=$(docker port "$postgres_container" | grep 5432 | cut -d: -f2 | head -1)
        postgres_port=${postgres_port:-5432}
        echo "postgresql://$db_user:$db_password@host.docker.internal:$postgres_port/$db_name"
    else
        # Use container networking
        echo "postgresql://$db_user:$db_password@$postgres_container:5432/$db_name"
    fi
}
generate_dynamic_name() {
    local base_name="$1"
    local counter=1
    local dynamic_name="$base_name"
    
    while docker ps -a --format '{{.Names}}' | grep -q "^${dynamic_name}$"; do
        dynamic_name="${base_name}-${counter}"
        ((counter++))
    done
    
    echo "$dynamic_name"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} RunAI Chat Dynamic Instance Deployment${NC}"
    echo -e "${BLUE}================================================${NC}"
}

show_help() {
    echo "Usage: $0 [postgres_container] [instance_suffix]"
    echo ""
    echo "Arguments:"
    echo "  postgres_container  - Name of PostgreSQL container (auto-detected if not provided)"
    echo "  instance_suffix     - Suffix for instance identification (timestamp if not provided)"
    echo ""
    echo "Examples:"
    echo "  $0                               # Auto-detect PostgreSQL, deploy with timestamp"
    echo "  $0 my-postgres-container         # Use specific PostgreSQL container"
    echo "  $0 my-postgres-container dev     # Use specific container with 'dev' suffix"
    echo ""
    echo "Features:"
    echo "  ✅ Automatic PostgreSQL container detection"
    echo "  ✅ Dynamic port allocation (starting from 3009)"
    echo "  ✅ Dynamic container naming with conflict resolution"
    echo "  ✅ Automatic database connection configuration"
    echo "  ✅ Network-aware deployment"
}

deploy_dynamic_openwebui() {
    local postgres_container="$1"
    local instance_suffix="${2:-$(date +%s)}"
    
    # Generate dynamic configuration
    local container_name=$(generate_dynamic_name "runai-openwebui")
    local port=$(find_available_port 3009)
    local volume_name="${container_name}_data"
    
    # Get database URL
    local database_url=$(get_postgres_connection "$postgres_container")
    
    # Get PostgreSQL network
    local postgres_network=$(docker inspect "$postgres_container" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
    
    print_status "Configuration:"
    echo "  Container Name: $container_name"
    echo "  Port: $port"
    echo "  Volume: $volume_name"
    echo "  Database: $database_url"
    echo "  Network: $postgres_network"
    
    # Deploy with dynamic configuration
    local docker_cmd="docker run -d \\
        --name \"$container_name\" \\
        -p $port:8080 \\
        -e DATABASE_URL='$database_url' \\
        -v \"$volume_name:/app/backend/data\" \\
        --restart unless-stopped"
    
    # Add network if not bridge
    if [ "$postgres_network" != "bridge" ] && [ -n "$postgres_network" ]; then
        docker_cmd="$docker_cmd \\
        --network \"$postgres_network\""
    fi
    
    docker_cmd="$docker_cmd \\
        ghcr.io/open-webui/open-webui:main"
    
    print_status "Deploying OpenWebUI instance..."
    eval "$docker_cmd"
    
    # Wait for health check
    print_status "Waiting for service to start..."
    sleep 15
    
    # Check status
    local container_status=$(docker ps --format '{{.Status}}' --filter name="$container_name")
    print_status "Container Status: $container_status"
    
    # Test connectivity
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" | grep -q "200\|302"; then
        print_status "✅ Instance is responding on port $port"
    else
        print_warning "⚠️ Instance may still be starting up"
    fi
    
    # Return connection info
    echo "SUCCESS:$container_name:$port:$database_url"
}

find_available_port() {
    local base_port="$1"
    local port="$base_port"
    
    while ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
    done
    
    echo "$port"
}

# Main deployment logic
main() {
    local postgres_container="$1"
    local instance_suffix="$2"
    
    print_header
    
    # Auto-detect PostgreSQL container if not provided
    if [ -z "$postgres_container" ]; then
        print_status "Auto-detecting PostgreSQL container..."
        postgres_container=$(docker ps --format '{{.Names}}' | grep -E "postgres|runai.*postgres" | head -1)
        
        if [ -z "$postgres_container" ]; then
            print_error "No PostgreSQL container found running!"
            echo ""
            echo "Available options:"
            echo "1. Deploy PostgreSQL first: cd ../database_util && ./deploy-runai-postgres.sh"
            echo "2. Or use docker-compose: docker-compose -f docker-compose.runai.yml up -d postgres"
            echo "3. Or deploy complete setup: ./deploy-dynamic.sh deploy multi"
            exit 1
        fi
        
        print_status "Found PostgreSQL container: $postgres_container"
    else
        # Verify specified container exists and is running
        if ! docker ps --format '{{.Names}}' | grep -q "^$postgres_container$"; then
            print_error "PostgreSQL container '$postgres_container' not found or not running!"
            echo ""
            echo "Running containers:"
            docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
            exit 1
        fi
        print_status "Using specified PostgreSQL container: $postgres_container"
    fi
    
    # Deploy the instance
    local result=$(deploy_dynamic_openwebui "$postgres_container" "$instance_suffix")
    
    if [[ $result == SUCCESS:* ]]; then
        # Parse result
        IFS=':' read -r status container_name port database_url <<< "$result"
        
        print_status "✅ Deployment completed successfully!"
        echo ""
        echo "=== INSTANCE INFORMATION ==="
        echo "Container Name: $container_name"
        echo "Access URL: http://localhost:$port"
        echo "Database: $database_url"
        echo ""
        echo "=== LOAD DISTRIBUTION STATUS ==="
        
        # List all OpenWebUI instances
        local instances=$(docker ps --format '{{.Names}}\t{{.Ports}}' | grep openwebui)
        if [ -n "$instances" ]; then
            echo "Active OpenWebUI instances:"
            echo "$instances" | while read -r name ports; do
                local port_num=$(echo "$ports" | grep -o '[0-9]*:8080' | cut -d: -f1)
                echo "  • $name: http://localhost:$port_num"
            done
        fi
        
        echo ""
        echo "🚀 Your RunAI Chat platform now supports load distribution!"
        echo "   All instances share the same database and user data."
        
        # Save deployment info
        echo "$(date -Iseconds):$container_name:$port:$postgres_container" >> .openwebui-instances.log
        
    else
        print_error "❌ Deployment failed!"
        exit 1
    fi
}

# Run main function with arguments
case "${1:-deploy}" in
    help)
        show_help
        ;;
    deploy|*)
        main "$1" "$2"
        ;;
esac