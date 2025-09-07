# Database Utilities

This directory contains all database-related scripts, backups, and utilities for the RunAI Chat platform.

## 🚀 **Dynamic Deployment Features**

### ✅ **Zero-Conflict Database Deployment**
- **Container names**: Auto-resolved if conflicts exist (`runai-postgres` → `runai-postgres-1`)
- **Port allocation**: Auto-increment from base port (5432 → 5433, 5434)
- **Volume names**: Dynamic naming prevents data overwrites
- **Connection strings**: Automatically generated for each deployment

### 🎯 **Quick Dynamic Deploy**
```bash
# Deploy with dynamic configuration
./deploy-runai-postgres.sh my-postgres my_user my_password

# Deploy second instance (auto-resolves conflicts)
./deploy-runai-postgres.sh my-postgres my_user my_password  # → my-postgres-1
```

> 📖 **See [../docker_deployment/DYNAMIC-DEPLOYMENT-GUIDE.md](../docker_deployment/DYNAMIC-DEPLOYMENT-GUIDE.md) for complete guide**

## 📁 Directory Structure

### 🗄️ Database Backups
- `openwebui_schema_backup.sql` - Complete database schema (24 tables)
- `openwebui_data_backup.sql` - Production data backup (8+ users, 52+ chats)
- `openwebui_complete_backup.sql` - Combined schema + data backup

### 🛠️ Deployment Scripts
- `deploy-runai-postgres.sh` - Deploy new PostgreSQL instances with RunAI schema
- `restore-runai-data.sh` - Restore data to existing PostgreSQL databases

### 🔄 Migration Scripts
- `openwebui-migration.py` - Comprehensive SQLite to PostgreSQL migration
- `improved-data-transfer.py` - Enhanced data transfer with type conversion
- `data-transfer.py` - Basic data transfer utility
- `simple-migration.py` - Simplified migration for quick transfers

### 🔐 Admin Utilities
- `reset-admin-password.py` - Reset admin password utility

### 🧪 Testing
- `test-database-utils.sh` - Comprehensive testing suite for all utilities

### 📋 SQL Utilities
- `verify-data.sql` - Data verification queries
- `final-verify.sql` - Final verification after migration
- `get-admin-info.sql` - Admin account information queries
- `fix-duplicates.sql` - Cleanup duplicate entries

---

## 🚀 Quick Start

### Deploy New PostgreSQL Database
```bash
# Deploy with custom configuration
./deploy-runai-postgres.sh my-postgres my_user my_password my_database 5432

# Connection string will be:
# postgresql://my_user:my_password@localhost:5432/my_database
```

### Restore Data to Existing Database
```bash
# Restore production data
./restore-runai-data.sh container_name username database_name
```

### Test All Utilities
```bash
# Run comprehensive test suite
./test-database-utils.sh

# Clean up test containers
./test-database-utils.sh cleanup
```

---

## 📊 Database Schema Information

### Tables (24 total)
- **User Management**: `user`, `auth`, `group`
- **Chat System**: `chat`, `message`, `chatidtag`, `message_reaction`
- **AI Models**: `model`, `function`, `tool`
- **Content**: `file`, `document`, `folder`, `knowledge`, `memory`, `note`
- **Organization**: `tag`, `prompt`, `feedback`, `config`
- **Channels**: `channel`, `channel_member`
- **Migration**: `alembic_version`, `migratehistory`

### Current Data (Production)
- **8+ Users** with active accounts
- **52+ Chat conversations** with full history
- **15+ AI Models** configured
- **18+ Tags** for organization
- **9+ Functions** (custom tools/plugins)
- **4+ Files** uploaded by users

---

## 🔧 Advanced Usage

### Custom Database Deployment
```bash
# Deploy for development
./deploy-runai-postgres.sh dev-postgres dev_user dev_pass runai_dev 5433

# Deploy for production
./deploy-runai-postgres.sh prod-postgres runai_user secure_pass_2024 runai_prod 5432

# Deploy for testing
./deploy-runai-postgres.sh test-postgres test_user test_pass test_db 5434
```

### Migration Scenarios
```bash
# Basic migration (recommended)
python3 improved-data-transfer.py

# Comprehensive migration with checks
python3 openwebui-migration.py

# Simple migration for testing
python3 simple-migration.py
```

### Data Verification
```bash
# After migration, verify data integrity
docker exec container_name psql -U username -d database -f verify-data.sql

# Get admin account information
docker exec container_name psql -U username -d database -f get-admin-info.sql
```

---

## ⚡ Testing & Validation

The `test-database-utils.sh` script provides comprehensive testing:

### What it tests:
- ✅ PostgreSQL deployment script functionality
- ✅ Data restoration script functionality  
- ✅ Backup file integrity and format
- ✅ Migration script syntax validation
- ✅ Schema deployment (24+ tables)
- ✅ Data restoration (users + chats)
- ✅ Database connection and health

### Test containers used:
- `test-postgres-1` (port 5440) - Schema deployment test
- `test-postgres-2` (port 5441) - Data restoration test

---

## 🔒 Security Best Practices

1. **Change Default Passwords**: Always use strong, unique passwords in production
2. **Backup Encryption**: Consider encrypting backup files for sensitive data
3. **Access Control**: Limit database access to authorized applications only
4. **Regular Backups**: Schedule automated backups with retention policies
5. **Connection Security**: Use SSL connections in production environments

---

## 🎯 Production Deployment Checklist

### Pre-Deployment
- [ ] Review backup files for completeness
- [ ] Test deployment scripts in staging environment
- [ ] Prepare production credentials
- [ ] Plan backup and recovery procedures
- [ ] Configure monitoring and alerting

### Deployment
- [ ] Deploy PostgreSQL with production credentials
- [ ] Restore data from backup
- [ ] Verify data integrity
- [ ] Test database connectivity
- [ ] Configure application connections

### Post-Deployment
- [ ] Monitor database performance
- [ ] Set up automated backups
- [ ] Test disaster recovery procedures
- [ ] Document connection details
- [ ] Train team on maintenance procedures

---

## 📞 Support & Troubleshooting

### Common Issues

**Script permissions**
```bash
chmod +x *.sh
```

**Database connection issues**
```bash
# Test connection manually
docker exec container_name pg_isready -U username -d database
```

**Migration errors**
```bash
# Check logs
docker logs container_name

# Verify schema
docker exec container_name psql -U username -d database -c "\dt"
```

### Admin Access
- **Email**: `shikhar@gameonn.cloud`
- **Role**: Admin with full access
- **Password Reset**: Use `reset-admin-password.py`

---

**Ready for enterprise-scale deployment! 🚀**