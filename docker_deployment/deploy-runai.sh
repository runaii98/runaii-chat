#!/bin/bash

# RunAI Chat Quick Deployment Script
# This script builds and deploys RunAI Chat with various configuration options

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

find_available_port() {
    local base_port="$1"
    local port="$base_port"
    
    while ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; do
        port=$((port + 1))
    done
    
    echo "$port"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} RunAI Chat Deployment Manager${NC}"
    echo -e "${BLUE}========================================${NC}"
}

show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Deployment options:"
    echo "  postgres-only     Build and run PostgreSQL with RunAI schema only"
    echo "  openwebui-single  Deploy single OpenWebUI instance with PostgreSQL"
    echo "  openwebui-multi   Deploy multiple OpenWebUI instances with load balancing"
    echo "  all-in-one       Deploy all-in-one container (PostgreSQL + OpenWebUI)"
    echo "  build-images     Build all Docker images"
    echo "  cleanup          Stop and remove all RunAI containers"
    echo "  help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 postgres-only"
    echo "  $0 openwebui-multi"
    echo "  $0 build-images"
}

build_images() {
    print_status "Building RunAI Chat Docker images..."
    
    # Build PostgreSQL image
    print_status "Building PostgreSQL image..."
    docker build -f Dockerfile.postgres -t runai-postgres:latest .
    
    # Build all-in-one image
    print_status "Building all-in-one image..."
    docker build -f Dockerfile.all-in-one -t runai-all-in-one:latest .
    
    print_status "All images built successfully!"
    docker images | grep runai
}

deploy_postgres_only() {
    print_status "Deploying PostgreSQL with RunAI schema..."
    
    # Generate dynamic names and ports
    local container_name=$(generate_dynamic_name "runai-postgres")
    local port=$(find_available_port 5432)
    
    print_status "Using container name: $container_name"
    print_status "Using port: $port"
    
    # Build image if it doesn't exist
    if ! docker images | grep -q runai-postgres; then
        print_status "Building PostgreSQL image..."
        docker build -f Dockerfile.postgres -t runai-postgres:latest .
    fi
    
    # Run container with dynamic settings
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -e POSTGRES_DB=runai_chat \
        -e POSTGRES_USER=runai_user \
        -e POSTGRES_PASSWORD=runai_secure_password \
        -p "$port:5432" \
        -v "${container_name}_data:/var/lib/postgresql/data" \
        runai-postgres:latest
    
    print_status "PostgreSQL deployed successfully!"
    print_status "Container: $container_name"
    print_status "Connection: postgresql://runai_user:runai_secure_password@localhost:$port/runai_chat"
}

deploy_openwebui_single() {
    print_status "Deploying single OpenWebUI instance..."
    
    # Generate dynamic names and ports
    local postgres_name=$(docker ps --format '{{.Names}}' | grep runai-postgres | head -1)
    local openwebui_name=$(generate_dynamic_name "runai-openwebui")
    local port=$(find_available_port 3001)
    
    # Ensure PostgreSQL is running
    if [ -z "$postgres_name" ]; then
        print_status "No PostgreSQL container found. Deploying one first..."
        deploy_postgres_only
        sleep 10
        postgres_name=$(docker ps --format '{{.Names}}' | grep runai-postgres | head -1)
    fi
    
    print_status "Using OpenWebUI container name: $openwebui_name"
    print_status "Using port: $port"
    print_status "Connecting to PostgreSQL: $postgres_name"
    
    # Deploy OpenWebUI
    docker run -d \
        --name "$openwebui_name" \
        --restart unless-stopped \
        --link "$postgres_name:postgres" \
        -e DATABASE_URL="postgresql://runai_user:runai_secure_password@postgres:5432/runai_chat" \
        -p "$port:8080" \
        -v "${openwebui_name}_data:/app/backend/data" \
        ghcr.io/open-webui/open-webui:main
    
    print_status "OpenWebUI deployed successfully!"
    print_status "Container: $openwebui_name"
    print_status "Access: http://localhost:$port"
}

deploy_openwebui_multi() {
    print_status "Deploying multiple OpenWebUI instances with load balancing..."
    
    # Copy environment file
    if [ ! -f .env ]; then
        cp .env.runai .env
        print_status "Created .env file. Please review and customize if needed."
    fi
    
    # Deploy with docker-compose
    docker-compose -f docker-compose.runai.yml --profile with-loadbalancer up -d
    
    print_status "Multi-instance deployment completed!"
    print_status "Load Balancer: http://localhost:80"
    print_status "OpenWebUI Instance 1: http://localhost:3001"
    print_status "OpenWebUI Instance 2: http://localhost:3009"
}

deploy_all_in_one() {
    print_status "Deploying all-in-one container..."
    
    # Generate dynamic names and ports
    local container_name=$(generate_dynamic_name "runai-allinone")
    local postgres_port=$(find_available_port 5432)
    local webui_port=$(find_available_port 3001)
    
    print_status "Using container name: $container_name"
    print_status "Using PostgreSQL port: $postgres_port"
    print_status "Using OpenWebUI port: $webui_port"
    
    # Build image if it doesn't exist
    if ! docker images | grep -q runai-all-in-one; then
        print_status "Building all-in-one image..."
        docker build -f Dockerfile.all-in-one -t runai-all-in-one:latest .
    fi
    
    # Run container
    docker run -d \
        --name "$container_name" \
        --restart unless-stopped \
        -p "$postgres_port:5432" \
        -p "$webui_port:8080" \
        -v "${container_name}_postgres:/var/lib/postgresql/14/main" \
        -v "${container_name}_webui:/app/backend/data" \
        runai-all-in-one:latest
    
    print_status "All-in-one deployment completed!"
    print_status "Container: $container_name"
    print_status "OpenWebUI: http://localhost:$webui_port"
    print_status "PostgreSQL: localhost:$postgres_port"
}

cleanup() {
    print_warning "This will stop and remove all RunAI containers and networks."
    read -p "Are you sure? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        print_status "Cleaning up RunAI containers..."
        
        # Stop and remove containers
        docker ps -a --format '{{.Names}}' | grep runai | xargs -r docker stop
        docker ps -a --format '{{.Names}}' | grep runai | xargs -r docker rm
        
        # Stop docker-compose services
        docker-compose -f docker-compose.runai.yml down --remove-orphans
        
        print_status "Cleanup completed!"
    else
        print_status "Cleanup cancelled."
    fi
}

# Main script
print_header

case "${1:-help}" in
    postgres-only)
        deploy_postgres_only
        ;;
    openwebui-single)
        deploy_openwebui_single
        ;;
    openwebui-multi)
        deploy_openwebui_multi
        ;;
    all-in-one)
        deploy_all_in_one
        ;;
    build-images)
        build_images
        ;;
    cleanup)
        cleanup
        ;;
    help|*)
        show_help
        ;;
esac