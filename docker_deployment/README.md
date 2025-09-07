# Docker Deployment

This directory contains all Docker-related files, configurations, and deployment scripts for the RunAI Chat platform.

## 🚀 **NEW: Dynamic Deployment System**

### ✅ **Zero-Conflict Deployments**
All scripts now automatically resolve:
- **Container name conflicts**: `runai-postgres` → `runai-postgres-1`, `runai-postgres-2`
- **Port conflicts**: Auto-increment from base port (5432 → 5433, 5434)
- **Volume name conflicts**: Dynamic naming prevents overwrites
- **Network conflicts**: Auto-detection and resolution

### 🎯 **Quick Dynamic Start**
```bash
# Deploy everything with load balancer
./deploy-dynamic.sh deploy full

# Deploy multi-instance setup
./deploy-dynamic.sh deploy multi

# Add more OpenWebUI instances
./deploy-second-openwebui.sh
```

> 📖 **See [DYNAMIC-DEPLOYMENT-GUIDE.md](./DYNAMIC-DEPLOYMENT-GUIDE.md) for complete dynamic deployment guide**

## 📁 Directory Structure

### 🐳 Docker Images
- `Dockerfile.postgres` - Custom PostgreSQL image with RunAI schema
- `Dockerfile.all-in-one` - Combined PostgreSQL + OpenWebUI container

### 🚀 Deployment Scripts
- `deploy-runai.sh` - Master deployment script for all scenarios
- `deploy-second-openwebui.sh` - Deploy second OpenWebUI instance for load distribution

### 🔧 Configuration Files
- `docker-compose.runai.yml` - Multi-instance deployment with load balancing
- `.env.runai` - Environment variables template
- `nginx.conf` - Load balancer configuration with rate limiting
- `supervisord.conf` - Process management for all-in-one container
- `start-services.sh` - Service startup script for all-in-one
- `init-runai-db.sh` - Database initialization script

### 🧪 Testing
- `test-docker-deployment.sh` - Comprehensive testing suite for all Docker components

---

## 🚀 Quick Start

### Single Instance Deployment
```bash
# Deploy PostgreSQL + OpenWebUI (development)
./deploy-runai.sh openwebui-single

# Access: http://localhost:3001
```

### Multi-Instance with Load Balancing (Production)
```bash
# Deploy with load balancer (your preferred setup!)
./deploy-runai.sh openwebui-multi

# Access: 
# - Load Balancer: http://localhost:80
# - Instance 1: http://localhost:3001
# - Instance 2: http://localhost:3009 (your preference!)
```

### All-in-One Container
```bash
# Single container with everything
./deploy-runai.sh all-in-one

# Access: http://localhost:3001
```

---

## 🎯 Load Distribution Strategy

Based on your preference for **multiple OpenWebUI instances sharing PostgreSQL**:

### Deploy Second Instance (Port 3009)
```bash
# Quick deployment of second instance
./deploy-second-openwebui.sh

# Result:
# • Instance 1: http://localhost:3001 ✅
# • Instance 2: http://localhost:3009 ✅ (Your preferred port!)
# • Shared PostgreSQL database ✅
```

### Full Load Balancing Setup
```bash
# Complete setup with NGINX load balancer
docker-compose -f docker-compose.runai.yml --profile with-loadbalancer up -d

# Services deployed:
# • PostgreSQL (shared database)
# • OpenWebUI Instance 1 (port 3001)
# • OpenWebUI Instance 2 (port 3009)
# • NGINX Load Balancer (port 80)
```

---

## 🐳 Docker Images

### Custom PostgreSQL Image
**Features:**
- Pre-configured with OpenWebUI schema (24 tables)
- Auto-initialization with production data
- Performance optimizations and indexes
- Health checks and monitoring
- Extensions: uuid-ossp, pg_trgm

**Build & Run:**
```bash
# Build image
docker build -f Dockerfile.postgres -t runai-postgres:latest .

# Run with custom config
docker run -d --name my-postgres \
  -e POSTGRES_DB=runai_chat \
  -e POSTGRES_USER=runai_user \
  -e POSTGRES_PASSWORD=secure_password \
  -p 5432:5432 \
  runai-postgres:latest
```

### All-in-One Image
**Features:**
- PostgreSQL + OpenWebUI in single container
- Supervisor process management
- Automatic service startup and health monitoring
- Perfect for demos and quick deployments

**Build & Run:**
```bash
# Build image
docker build -f Dockerfile.all-in-one -t runai-allinone:latest .

# Run complete stack
docker run -d --name runai-complete \
  -p 5432:5432 -p 3001:8080 \
  runai-allinone:latest
```

---

## ⚖️ Load Balancer Configuration

### NGINX Features
- **Round-robin load balancing** between OpenWebUI instances
- **Rate limiting**: 10 req/s for API, 5 req/m for login
- **WebSocket support** for real-time chat
- **Health checks** and automatic failover
- **Security headers** (XSS protection, frame options)
- **SSL-ready** configuration

### Configuration Highlights
```nginx
upstream openwebui_backend {
    server runai-openwebui-1:8080 weight=1;
    server runai-openwebui-2:8080 weight=1;
}

# Rate limiting zones
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
```

---

## 🛠️ Deployment Scenarios

### Scenario 1: Development Environment
```bash
# Single instance for development
./deploy-runai.sh postgres-only
./deploy-runai.sh openwebui-single
```

### Scenario 2: Production with Load Distribution
```bash
# Your preferred setup!
./deploy-runai.sh openwebui-multi

# Or step-by-step:
./deploy-runai.sh postgres-only
./deploy-second-openwebui.sh  # Deploys on port 3009
```

### Scenario 3: Rapid Deployment/Demo
```bash
# Everything in one container
./deploy-runai.sh all-in-one
```

### Scenario 4: Custom Scaling
```bash
# Build images first
./deploy-runai.sh build-images

# Deploy multiple PostgreSQL instances
./deploy-runai-postgres.sh postgres-1 user1 pass1 db1 5432
./deploy-runai-postgres.sh postgres-2 user2 pass2 db2 5433

# Deploy OpenWebUI instances pointing to different databases
```

---

## 🧪 Testing & Validation

### Comprehensive Test Suite
```bash
# Run all tests
./test-docker-deployment.sh

# Quick syntax tests only
./test-docker-deployment.sh quick

# Cleanup test containers
./test-docker-deployment.sh cleanup
```

### What the test suite validates:
- ✅ Dockerfile syntax and build success
- ✅ Docker Compose configuration validity
- ✅ NGINX load balancer configuration
- ✅ Deployment script syntax
- ✅ PostgreSQL image build and functionality
- ✅ All-in-One image build and services
- ✅ Load distribution (2 OpenWebUI instances)
- ✅ Network connectivity between containers
- ✅ Health checks and service startup

### Test Containers Created:
- `test-postgres-docker` - PostgreSQL image test
- `test-allinone-docker` - All-in-One image test
- `test-openwebui-1` - First OpenWebUI instance
- `test-openwebui-2` - Second OpenWebUI instance (load distribution)
- `test-nginx-lb` - Load balancer test

---

## ⚙️ Environment Configuration

### Environment Variables (.env.runai)
```bash
# PostgreSQL Configuration
POSTGRES_DB=runai_chat
POSTGRES_USER=runai_user
POSTGRES_PASSWORD=runai_secure_password_2024
POSTGRES_PORT=5432

# OpenWebUI Configuration
OPENWEBUI_PORT_1=3001
OPENWEBUI_PORT_2=3009  # Your preferred second instance port!
WEBUI_SECRET_KEY=your-super-secret-key

# Load Balancer
NGINX_PORT=80
```

### Customization Examples
```bash
# Development environment
POSTGRES_PASSWORD=dev_password
OPENWEBUI_PORT_1=3001
OPENWEBUI_PORT_2=3009
NGINX_PORT=8080

# Production environment
POSTGRES_PASSWORD=prod_secure_password_2024
OPENWEBUI_PORT_1=3001
OPENWEBUI_PORT_2=3009
NGINX_PORT=80
```

---

## 📊 Production Monitoring

### Health Check Endpoints
- **Load Balancer**: `http://localhost/health`
- **NGINX Status**: `http://localhost/nginx_status` (local only)
- **PostgreSQL**: `pg_isready` command in container
- **OpenWebUI**: Built-in health checks on each instance

### Container Status Monitoring
```bash
# Check all RunAI containers
docker ps | grep runai

# Check specific container health
docker inspect --format='{{.State.Health.Status}}' container_name

# View container logs
docker logs runai-openwebui-1
docker logs runai-postgres
```

---

## 🔒 Security Configuration

### Network Security
- Containers isolated in custom networks
- Only necessary ports exposed
- Internal communication via container names

### Application Security
- Rate limiting via NGINX
- Security headers enabled
- WebSocket connections secured
- SSL-ready configuration

### Database Security
- Non-root database user
- Password-based authentication
- Connection pooling support
- Backup encryption ready

---

## 🎯 Production Deployment Checklist

### Pre-Deployment
- [ ] Copy and customize `.env.runai` to `.env`
- [ ] Review security settings
- [ ] Plan backup and monitoring
- [ ] Test in staging environment

### Deployment
- [ ] Run comprehensive tests: `./test-docker-deployment.sh`
- [ ] Deploy chosen scenario: `./deploy-runai.sh <scenario>`
- [ ] Verify all services are healthy
- [ ] Test load distribution (if using multi-instance)

### Post-Deployment
- [ ] Configure monitoring and alerting
- [ ] Set up automated backups
- [ ] Document deployed configuration
- [ ] Train team on maintenance procedures

---

## 🚀 Scaling Your AI Startup

### Horizontal Scaling
```bash
# Add more OpenWebUI instances
docker run -d --name runai-openwebui-3 \
  --network runai-network \
  -p 3012:8080 \
  -e DATABASE_URL="postgresql://user:pass@postgres:5432/db" \
  ghcr.io/open-webui/open-webui:main

# Update NGINX config to include new instance
```

### Database Scaling
```bash
# Deploy dedicated database server
./deploy-runai-postgres.sh prod-postgres runai_user secure_pass runai_prod 5432

# Update all OpenWebUI instances to use new database
```

### Geographic Distribution
```bash
# Deploy in different regions
./deploy-runai.sh openwebui-multi  # Region 1
./deploy-runai.sh openwebui-multi  # Region 2

# Configure DNS load balancing between regions
```

---

## 📞 Support & Troubleshooting

### Common Issues

**Container startup failures**
```bash
# Check logs
docker logs container_name

# Check ports
docker ps | grep runai
```

**Load balancer not working**
```bash
# Test NGINX config
docker exec nginx-container nginx -t

# Check upstream health
curl http://localhost/health
```

**Database connection issues**
```bash
# Test database connectivity
docker exec postgres-container pg_isready -U username -d database
```

### Performance Optimization
- Use SSD storage for database volumes
- Increase PostgreSQL shared_buffers for large datasets
- Configure connection pooling for high traffic
- Monitor container resource usage

---

**Ready to scale your AI startup! 🚀**

Your load distribution strategy with multiple OpenWebUI instances on ports 3001 and 3009 sharing the same PostgreSQL database is fully implemented and tested!