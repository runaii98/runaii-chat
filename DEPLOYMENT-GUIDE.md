 script dynamic too, # RunAI Chat Deployment & Scaling Guide

## 🚀 Overview

This repository contains everything you need to deploy and scale your RunAI Chat platform with PostgreSQL and OpenWebUI. Created specifically for AI startups that need reliable, scalable infrastructure.

## 📁 What's Included

### 🗄️ Database Backups
- `openwebui_schema_backup.sql` - Complete database schema
- `openwebui_data_backup.sql` - Production data backup (8 users, 52 chats)
- `openwebui_complete_backup.sql` - Combined schema + data

### 🛠️ Deployment Scripts
- `deploy-runai-postgres.sh` - Deploy PostgreSQL with custom config
- `restore-runai-data.sh` - Restore data to existing database
- `deploy-runai.sh` - Master deployment script for all scenarios

### 🐳 Docker Images
- `Dockerfile.postgres` - Custom PostgreSQL with RunAI schema
- `Dockerfile.all-in-one` - Combined PostgreSQL + OpenWebUI
- `docker-compose.runai.yml` - Multi-instance with load balancing

### ⚙️ Configuration Files
- `.env.runai` - Environment variables template
- `nginx.conf` - Load balancer configuration
- `supervisord.conf` - Process management for all-in-one
- `init-runai-db.sh` - Database initialization script

---

## 🚀 Quick Start

### Option 1: Single Instance (Development)
```bash
# Deploy PostgreSQL + OpenWebUI
./deploy-runai.sh openwebui-single

# Access: http://localhost:3001
# Login: shikhar@gameonn.cloud / admin123
```

### Option 2: Multi-Instance with Load Balancing (Production)
```bash
# Deploy with load balancer
./deploy-runai.sh openwebui-multi

# Access: http://localhost:80 (load balanced)
# Direct: http://localhost:3001, http://localhost:3009
```

### Option 3: All-in-One Container (Easy Deployment)
```bash
# Single container with everything
./deploy-runai.sh all-in-one

# Access: http://localhost:3001
```

---

## 📊 Scaling Scenarios

### Scenario 1: Database Scaling
**When**: Growing user base needs dedicated database

```bash
# 1. Deploy dedicated PostgreSQL
./deploy-runai-postgres.sh runai-postgres-prod runai_user secure_password runai_chat 5432

# 2. Restore production data
./restore-runai-data.sh runai-postgres-prod runai_user runai_chat

# 3. Update OpenWebUI containers to point to new database
docker run -d --name openwebui-1 \
  -e DATABASE_URL="postgresql://runai_user:secure_password@runai-postgres-prod:5432/runai_chat" \
  -p 3001:8080 ghcr.io/open-webui/open-webui:main
```

### Scenario 2: Frontend Load Distribution  
**When**: High traffic needs multiple OpenWebUI instances

```bash
# Deploy multiple instances sharing same database
docker-compose -f docker-compose.runai.yml up -d

# Scales to:
# - 1x PostgreSQL (shared)
# - 2x OpenWebUI instances (ports 3001, 3009)
# - 1x NGINX load balancer (port 80)
```

### Scenario 3: Rapid Deployment
**When**: Need quick deployment for demos/testing

```bash
# Build all images once
./deploy-runai.sh build-images

# Deploy anywhere instantly
./deploy-runai.sh all-in-one
```

---

## 🔧 Advanced Configuration

### Environment Variables
```bash
# Database Configuration
POSTGRES_DB=runai_chat
POSTGRES_USER=runai_user  
POSTGRES_PASSWORD=secure_password_2024
POSTGRES_PORT=5432

# OpenWebUI Configuration  
OPENWEBUI_PORT_1=3001
OPENWEBUI_PORT_2=3009
WEBUI_SECRET_KEY=your-secret-key

# Load Balancer
NGINX_PORT=80
```

### Custom Database Deployment
```bash
# Deploy with custom credentials
./deploy-runai-postgres.sh my-postgres my_user my_password my_database 5433

# Connection string will be:
# postgresql://my_user:my_password@localhost:5433/my_database
```

### Load Balancer Configuration
The included NGINX config provides:
- Round-robin load balancing
- Rate limiting (10 req/s for API, 5 req/m for login)
- WebSocket support
- Health checks
- Security headers

---

## 📈 Performance Tuning

### PostgreSQL Optimization
```sql
-- Add these to PostgreSQL config for better performance
shared_buffers = 256MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
```

### OpenWebUI Scaling
- **CPU**: Each OpenWebUI instance: 1-2 CPU cores
- **Memory**: 512MB - 1GB per instance
- **Storage**: Shared volume for file uploads
- **Database**: Connection pooling recommended for 10+ instances

---

## 🔒 Security Best Practices

### Database Security
1. **Change default passwords** in production
2. **Use SSL connections** for remote databases
3. **Limit network access** with firewall rules
4. **Regular backups** with encryption

### Application Security
1. **Generate unique WEBUI_SECRET_KEY** 
2. **Use HTTPS** in production
3. **Configure rate limiting** via NGINX
4. **Enable audit logging**

---

## 🗂️ Backup & Recovery

### Automated Backups
```bash
# Create backup
docker exec runai-postgres-prod pg_dump -U runai_user -d runai_chat > backup_$(date +%Y%m%d).sql

# Restore backup
./restore-runai-data.sh runai-postgres-prod runai_user runai_chat
```

### Disaster Recovery
1. **Schema**: Always available in `openwebui_schema_backup.sql`
2. **Data**: Regular dumps in `openwebui_data_backup.sql` 
3. **Config**: All configs version controlled in this repo

---

## 🎯 Production Deployment Checklist

### Pre-Deployment
- [ ] Review and customize `.env` file
- [ ] Change default passwords
- [ ] Generate secure WEBUI_SECRET_KEY
- [ ] Configure firewall rules
- [ ] Set up monitoring

### Post-Deployment  
- [ ] Test all endpoints
- [ ] Verify database connectivity
- [ ] Check load balancer health
- [ ] Test admin login
- [ ] Configure backups
- [ ] Set up monitoring/alerting

---

## 🔧 Troubleshooting

### Common Issues

**Container won't start**
```bash
# Check logs
docker logs runai-postgres-prod
docker logs runai-openwebui-1

# Check ports
ss -tuln | grep 5432
ss -tuln | grep 3001
```

**Database connection issues**
```bash
# Test connection
docker exec runai-postgres-prod pg_isready -U runai_user -d runai_chat

# Reset permissions
docker exec runai-postgres-prod psql -U runai_user -d runai_chat -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO runai_user;"
```

**Load balancer not working**
```bash
# Check NGINX config
docker exec runai-loadbalancer nginx -t

# Check upstream health
curl http://localhost/health
```

---

## 📞 Support

### Admin Access
- **Email**: `shikhar@gameonn.cloud`
- **Password**: `admin123` (change in production!)
- **Role**: Full admin access

### Monitoring Endpoints
- Load Balancer Health: `http://localhost/health`
- NGINX Status: `http://localhost/nginx_status` (local only)
- Database Health: `pg_isready` command

---

## 🚀 Your AI Startup is Ready!

This deployment system gives you:
✅ **Scalable PostgreSQL** with your data preserved  
✅ **Load-balanced OpenWebUI** for high availability  
✅ **Container orchestration** for easy scaling  
✅ **Production-ready** with security and monitoring  
✅ **Disaster recovery** with automated backups  

Deploy with confidence and scale as your startup grows! 🎯