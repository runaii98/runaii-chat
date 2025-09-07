#!/bin/bash

# RunAI Chat Dynamic Deployment Script
# This script automatically resolves naming and port conflicts
# and generates unique configurations for each deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[DYNAMIC]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE} RunAI Chat Dynamic Deployment System${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# Generate dynamic container name
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

# Find available port
find_available_port() {
    local base_port="$1"
    local port="$base_port"
    
    while ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
    done
    
    echo "$port"
}

# Check if network exists
check_network() {
    local network_name="$1"
    local counter=1
    local dynamic_network="$network_name"
    
    while docker network ls --format '{{.Name}}' | grep -q "^${dynamic_network}$"; do
        dynamic_network="${network_name}-${counter}"
        ((counter++))
    done
    
    echo "$dynamic_network"
}

# Generate dynamic environment file
generate_dynamic_env() {
    local deployment_id="$1"
    local env_file=".env.dynamic-${deployment_id}"
    
    # Base configuration
    local postgres_container=$(generate_dynamic_name "runai-postgres")
    local openwebui_1_container=$(generate_dynamic_name "runai-openwebui-1")
    local openwebui_2_container=$(generate_dynamic_name "runai-openwebui-2")
    local nginx_container=$(generate_dynamic_name "runai-loadbalancer")
    local network_name=$(check_network "runai-network")
    
    # Find available ports
    local postgres_port=$(find_available_port 5432)
    local openwebui_port_1=$(find_available_port 3001)
    local openwebui_port_2=$(find_available_port 3009)
    local nginx_port=$(find_available_port 80)
    
    print_status "Generating dynamic configuration:"
    echo "  PostgreSQL: $postgres_container (port $postgres_port)"
    echo "  OpenWebUI-1: $openwebui_1_container (port $openwebui_port_1)"
    echo "  OpenWebUI-2: $openwebui_2_container (port $openwebui_port_2)"
    echo "  Load Balancer: $nginx_container (port $nginx_port)"
    echo "  Network: $network_name"
    echo "  Environment file: $env_file"
    
    # Create dynamic environment file
    cat > "$env_file" << EOF
# Auto-generated dynamic environment file for deployment ID: $deployment_id
# Generated on: $(date)

# PostgreSQL Configuration
POSTGRES_DB=runai_chat
POSTGRES_USER=runai_user
POSTGRES_PASSWORD=runai_secure_password_$(date +%s)
POSTGRES_PORT=$postgres_port
POSTGRES_CONTAINER=$postgres_container

# OpenWebUI Configuration
OPENWEBUI_PORT_1=$openwebui_port_1
OPENWEBUI_PORT_2=$openwebui_port_2
OPENWEBUI_1_CONTAINER=$openwebui_1_container
OPENWEBUI_2_CONTAINER=$openwebui_2_container
WEBUI_SECRET_KEY=dynamic-secret-key-$(openssl rand -hex 16)

# NGINX Load Balancer
NGINX_PORT=$nginx_port
NGINX_CONTAINER=$nginx_container

# Network Configuration
NETWORK_NAME=$network_name

# Deployment Metadata
DEPLOYMENT_ID=$deployment_id
DEPLOYMENT_TIMESTAMP=$(date -Iseconds)
EOF

    echo "$env_file"
}

# Deploy with dynamic configuration
deploy_dynamic() {
    local deployment_type="$1"
    local deployment_id="${2:-$(date +%Y%m%d-%H%M%S)}"
    
    print_status "Starting dynamic deployment..."
    print_status "Deployment Type: $deployment_type"
    print_status "Deployment ID: $deployment_id"
    
    # Generate dynamic environment
    local env_file=$(generate_dynamic_env "$deployment_id")
    
    case "$deployment_type" in
        "full")
            print_status "Deploying full multi-instance setup with load balancer..."
            docker-compose -f docker-compose.runai.yml --env-file "$env_file" --profile with-loadbalancer up -d
            ;;
        "multi")
            print_status "Deploying multi-instance setup (no load balancer)..."
            docker-compose -f docker-compose.runai.yml --env-file "$env_file" up -d
            ;;
        "single")
            print_status "Deploying single instance..."
            docker-compose -f docker-compose.runai.yml --env-file "$env_file" up -d postgres openwebui-1
            ;;
        "postgres-only")
            print_status "Deploying PostgreSQL only..."
            docker-compose -f docker-compose.runai.yml --env-file "$env_file" up -d postgres
            ;;
        *)
            print_error "Unknown deployment type: $deployment_type"
            print_error "Available types: full, multi, single, postgres-only"
            return 1
            ;;
    esac
    
    # Show deployment summary
    print_status "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Deployment ID: $deployment_id"
    echo "Environment File: $env_file"
    echo ""
    
    # Source the environment file to show access URLs
    source "$env_file"
    
    if [[ "$deployment_type" == "full" ]]; then
        echo "🌐 NGINX Load Balancer: http://localhost:$NGINX_PORT"
    fi
    
    if [[ "$deployment_type" != "postgres-only" ]]; then
        echo "🖥️ OpenWebUI Instance 1: http://localhost:$OPENWEBUI_PORT_1"
        if [[ "$deployment_type" == "full" || "$deployment_type" == "multi" ]]; then
            echo "🖥️ OpenWebUI Instance 2: http://localhost:$OPENWEBUI_PORT_2"
        fi
    fi
    
    echo "🗄️ PostgreSQL: localhost:$POSTGRES_PORT"
    echo "🔗 Database URL: postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/$POSTGRES_DB"
    echo ""
    echo "📝 Environment file saved as: $env_file"
    echo "   Keep this file to manage this deployment!"
    echo ""
    
    # Save deployment info
    echo "$deployment_id:$env_file:$(date)" >> .deployments.log
}

# List active deployments
list_deployments() {
    print_status "Active RunAI Chat deployments:"
    echo ""
    
    if [ -f .deployments.log ]; then
        while IFS=':' read -r dep_id env_file timestamp; do
            if [ -f "$env_file" ]; then
                source "$env_file"
                echo "🚀 $dep_id (deployed $timestamp)"
                echo "   Environment: $env_file"
                echo "   PostgreSQL: localhost:$POSTGRES_PORT ($POSTGRES_CONTAINER)"
                if [ -n "$OPENWEBUI_PORT_1" ]; then
                    echo "   OpenWebUI-1: localhost:$OPENWEBUI_PORT_1 ($OPENWEBUI_1_CONTAINER)"
                fi
                if [ -n "$OPENWEBUI_PORT_2" ]; then
                    echo "   OpenWebUI-2: localhost:$OPENWEBUI_PORT_2 ($OPENWEBUI_2_CONTAINER)"
                fi
                echo ""
            fi
        done < .deployments.log
    else
        echo "No deployments found."
    fi
}

# Cleanup deployment
cleanup_deployment() {
    local deployment_id="$1"
    
    if [ -z "$deployment_id" ]; then
        print_error "Please specify deployment ID to cleanup"
        list_deployments
        return 1
    fi
    
    local env_file=".env.dynamic-${deployment_id}"
    
    if [ ! -f "$env_file" ]; then
        print_error "Environment file $env_file not found"
        return 1
    fi
    
    print_status "Cleaning up deployment: $deployment_id"
    
    # Stop and remove containers
    docker-compose -f docker-compose.runai.yml --env-file "$env_file" down --remove-orphans -v
    
    # Remove environment file
    rm -f "$env_file"
    
    # Remove from deployments log
    if [ -f .deployments.log ]; then
        grep -v "^$deployment_id:" .deployments.log > .deployments.log.tmp || true
        mv .deployments.log.tmp .deployments.log
    fi
    
    print_status "Cleanup completed for deployment: $deployment_id"
}

show_help() {
    echo "RunAI Chat Dynamic Deployment System"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy <type> [id]     Deploy with automatic conflict resolution"
    echo "                         Types: full, multi, single, postgres-only"
    echo "  list                   List all active deployments"
    echo "  cleanup <id>           Remove specific deployment"
    echo "  cleanup-all            Remove all deployments"
    echo "  help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy full                    # Deploy everything with load balancer"
    echo "  $0 deploy multi my-test          # Deploy multi-instance with custom ID"
    echo "  $0 deploy single                 # Deploy single instance only"
    echo "  $0 list                          # Show all deployments"
    echo "  $0 cleanup my-test               # Remove specific deployment"
    echo ""
    echo "Features:"
    echo "  ✅ Automatic container name conflict resolution"
    echo "  ✅ Automatic port conflict resolution"
    echo "  ✅ Dynamic environment generation"
    echo "  ✅ Multiple deployment management"
    echo "  ✅ Complete cleanup capabilities"
}

# Main script
print_header

case "${1:-help}" in
    deploy)
        if [ -z "$2" ]; then
            print_error "Please specify deployment type"
            show_help
        else
            deploy_dynamic "$2" "$3"
        fi
        ;;
    list)
        list_deployments
        ;;
    cleanup)
        if [ "$2" = "all" ]; then
            print_warning "This will remove ALL RunAI Chat deployments!"
            read -p "Are you sure? (y/N): " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                # Cleanup all
                for env_file in .env.dynamic-*; do
                    if [ -f "$env_file" ]; then
                        docker-compose -f docker-compose.runai.yml --env-file "$env_file" down --remove-orphans -v 2>/dev/null || true
                        rm -f "$env_file"
                    fi
                done
                rm -f .deployments.log
                print_status "All deployments cleaned up"
            fi
        else
            cleanup_deployment "$2"
        fi
        ;;
    help|*)
        show_help
        ;;
esac