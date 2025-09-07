#!/bin/bash

# LiteLLM Load Distribution Deployment Script
# This script deploys additional LiteLLM instances connected to shared PostgreSQL

set -e

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[LITELLM-DEPLOY]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} LiteLLM Load Distribution Deployment${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Dynamic configuration functions
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

find_available_port() {
    local base_port="$1"
    local port="$base_port"
    
    while ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
    done
    
    echo "$port"
}

# Auto-detect PostgreSQL container for LiteLLM
get_postgres_litellm_info() {
    local postgres_container=$(docker ps --format '{{.Names}}' | grep -E "postgres.*litellm|litellm.*postgres" | head -1)
    
    if [ -z "$postgres_container" ]; then
        # Check for container file from migration script
        if [ -f ".litellm_postgres_container" ]; then
            postgres_container=$(cat .litellm_postgres_container)
        else
            print_error "No PostgreSQL container found for LiteLLM!"
            echo "Please run migrate-litellm-to-postgres.sh first"
            exit 1
        fi
    fi
    
    # Get database connection details
    local db_user=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_USER=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    local db_password=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_PASSWORD=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    local db_name=$(docker inspect "$postgres_container" --format '{{range .Config.Env}}{{if (contains . "POSTGRES_DB=")}}{{.}}{{end}}{{end}}' | cut -d= -f2)
    
    # Default values
    db_user=${db_user:-litellm_user}
    db_password=${db_password:-litellm_secure_password_2024}
    db_name=${db_name:-litellm_db}
    
    # Get port information
    local postgres_port=$(docker port "$postgres_container" | grep 5432 | cut -d: -f2 | head -1)
    postgres_port=${postgres_port:-5433}
    
    # Get network information
    local network=$(docker inspect "$postgres_container" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' | head -1)
    
    if [ "$network" = "bridge" ] || [ -z "$network" ]; then
        echo "postgresql://$db_user:$db_password@host.docker.internal:$postgres_port/$db_name"
    else
        echo "postgresql://$db_user:$db_password@$postgres_container:5432/$db_name"
    fi
}

# Deploy LiteLLM instance with PostgreSQL connection
deploy_litellm_instance() {
    local instance_suffix="${1:-$(date +%s)}"
    local base_port="${2:-4001}"
    
    print_header
    print_status "Deploying LiteLLM instance with PostgreSQL connection..."
    
    # Generate dynamic configuration
    local container_name=$(generate_dynamic_name "litellm")
    local port=$(find_available_port "$base_port")
    local volume_name="${container_name}_data"
    
    # Get PostgreSQL database URL
    local database_url=$(get_postgres_litellm_info)
    
    print_status "Configuration:"
    echo "  Container Name: $container_name"
    echo "  Port: $port"
    echo "  Volume: $volume_name"
    echo "  Database: $database_url"
    
    # Deploy LiteLLM with PostgreSQL connection
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -p "$port:4000" \
        -e DATABASE_URL="$database_url" \
        -e LITELLM_MASTER_KEY="sk-1234" \
        -e LITELLM_SALT_KEY="sk-1234" \
        -v "$volume_name:/app/data" \
        ghcr.io/berriai/litellm:main-latest
    
    # Wait for service to start
    print_status "Waiting for LiteLLM to start..."
    sleep 15
    
    # Check status
    local container_status=$(docker ps --format '{{.Status}}' --filter name="$container_name")
    print_status "Container Status: $container_status"
    
    # Test connectivity
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/health" | grep -q "200"; then
        print_status "✅ LiteLLM instance is responding on port $port"
    else
        print_warning "⚠️ LiteLLM instance may still be starting up"
    fi
    
    # Save deployment info
    echo "$(date -Iseconds):$container_name:$port:$database_url" >> .litellm-instances.log
    
    print_status "✅ LiteLLM instance deployed successfully!"
    echo ""
    echo "🌐 Access URL: http://localhost:$port"
    echo "🔗 Database: $database_url"
    echo "🔑 Master Key: sk-1234"
    
    return 0
}

# Update existing LiteLLM instance to use PostgreSQL
update_existing_litellm() {
    print_status "Updating existing LiteLLM instance to use PostgreSQL..."
    
    # Find existing LiteLLM container
    local existing_container=$(docker ps --format '{{.Names}}' | grep litellm | head -1)
    
    if [ -z "$existing_container" ]; then
        print_error "No existing LiteLLM container found"
        return 1
    fi
    
    print_status "Found existing LiteLLM container: $existing_container"
    
    # Get current port
    local current_port=$(docker port "$existing_container" | grep 4000 | cut -d: -f2 | head -1)
    current_port=${current_port:-4000}
    
    # Get PostgreSQL database URL
    local database_url=$(get_postgres_litellm_info)
    
    print_status "Stopping existing container..."
    docker stop "$existing_container"
    
    print_status "Updating container with PostgreSQL connection..."
    docker run -d \
        --name "${existing_container}-postgres" \
        --restart unless-stopped \
        -p "$current_port:4000" \
        -e DATABASE_URL="$database_url" \
        -e LITELLM_MASTER_KEY="sk-1234" \
        -e LITELLM_SALT_KEY="sk-1234" \
        -v "${existing_container}_postgres_data:/app/data" \
        ghcr.io/berriai/litellm:main-latest
    
    # Remove old container
    docker rm "$existing_container"
    
    print_status "✅ Existing LiteLLM instance updated to use PostgreSQL"
    print_status "🌐 Still accessible at: http://localhost:$current_port"
}

# List all LiteLLM instances
list_litellm_instances() {
    print_status "Active LiteLLM instances:"
    echo ""
    
    local instances=$(docker ps --format '{{.Names}}\t{{.Ports}}' | grep litellm)
    if [ -n "$instances" ]; then
        echo "📋 Running instances:"
        echo "$instances" | while read -r name ports; do
            local port_num=$(echo "$ports" | grep -o '[0-9]*:4000' | cut -d: -f1)
            echo "  • $name: http://localhost:$port_num"
        done
    else
        echo "No LiteLLM instances found"
    fi
    
    echo ""
    
    if [ -f ".litellm-instances.log" ]; then
        echo "📝 Deployment history:"
        cat .litellm-instances.log
    fi
}

# Main function
main() {
    local action="${1:-help}"
    
    case "$action" in
        deploy)
            deploy_litellm_instance "$2" "$3"
            ;;
        update)
            update_existing_litellm
            ;;
        list)
            list_litellm_instances
            ;;
        help|*)
            echo "Usage: $0 <action> [options]"
            echo ""
            echo "Actions:"
            echo "  deploy [suffix] [port]  Deploy new LiteLLM instance"
            echo "  update                  Update existing LiteLLM to use PostgreSQL"
            echo "  list                    List all LiteLLM instances"
            echo "  help                    Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 deploy                    # Deploy with auto-generated suffix"
            echo "  $0 deploy instance-2 4001    # Deploy on specific port"
            echo "  $0 update                    # Update existing instance"
            echo "  $0 list                      # List all instances"
            ;;
    esac
}

# Execute main function
main "$@"