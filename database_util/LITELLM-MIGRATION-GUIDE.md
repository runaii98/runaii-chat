# 🚀 LiteLLM Load Distribution Setup Guide

## Step-by-Step Migration Process

### 📋 **Prerequisites**
- SSH access to your dev server: `ssh -i /Users/mrcool/Desktop/key/runaii-chat-dev-server-1.pem azureuser@40.81.240.134`
- LiteLLM container running at http://40.81.240.134:4000
- Docker and basic tools available

### 🎯 **Execution Commands**

#### **Step 1: Upload Scripts to Dev Server**
```bash
# On your local machine - upload the scripts
scp -i /Users/mrcool/Desktop/key/runaii-chat-dev-server-1.pem \
    database_util/migrate-litellm-to-postgres.sh \
    database_util/test-litellm-migration.sh \
    docker_deployment/deploy-litellm-loadbalance.sh \
    azureuser@40.81.240.134:~/
```

#### **Step 2: Connect to Dev Server**
```bash
ssh -i /Users/mrcool/Desktop/key/runaii-chat-dev-server-1.pem azureuser@40.81.240.134
```

#### **Step 3: Make Scripts Executable**
```bash
chmod +x migrate-litellm-to-postgres.sh
chmod +x deploy-litellm-loadbalance.sh  
chmod +x test-litellm-migration.sh
```

#### **Step 4: Run Migration (Creates postgres_litellm)**
```bash
# This will:
# - Analyze current LiteLLM setup
# - Backup existing data
# - Deploy PostgreSQL container named "postgres-litellm"
# - Extract and convert schema
# - Migrate all data
# - Verify migration
./migrate-litellm-to-postgres.sh
```

#### **Step 5: Update Existing LiteLLM Instance**
```bash
# Update your current LiteLLM to use PostgreSQL
./deploy-litellm-loadbalance.sh update
```

#### **Step 6: Deploy Additional LiteLLM Instances**
```bash
# Deploy second instance for load distribution
./deploy-litellm-loadbalance.sh deploy instance-2 4001

# Deploy third instance
./deploy-litellm-loadbalance.sh deploy instance-3 4002

# List all instances
./deploy-litellm-loadbalance.sh list
```

#### **Step 7: Test Everything**
```bash
# Run comprehensive tests
./test-litellm-migration.sh all

# Test specific components
./test-litellm-migration.sh postgres     # Test PostgreSQL
./test-litellm-migration.sh instances    # Test LiteLLM instances  
./test-litellm-migration.sh consistency  # Test data consistency
./test-litellm-migration.sh load         # Test load distribution

# Show deployment summary
./test-litellm-migration.sh summary
```

### 🔍 **Verification Checklist**

#### **Database Migration Verification**
- [ ] PostgreSQL container "postgres-litellm" created and running
- [ ] All LiteLLM tables migrated successfully
- [ ] All records copied (verify counts match)
- [ ] Schema integrity maintained
- [ ] Database connection working

#### **Load Distribution Verification**  
- [ ] Multiple LiteLLM instances running on different ports
- [ ] All instances connected to shared PostgreSQL
- [ ] Health endpoints responding (HTTP 200)
- [ ] Models endpoint working on all instances
- [ ] Database consistency across instances

#### **Expected Results**
```bash
# PostgreSQL Container
postgres-litellm         # Running on port 5433

# LiteLLM Instances (Load Distributed)
litellm                  # Original instance - port 4000
litellm-1               # Second instance - port 4001  
litellm-2               # Third instance - port 4002

# All instances share: postgresql://litellm_user:password@postgres-litellm:5432/litellm_db
```

### 🌐 **Access URLs After Setup**
- **LiteLLM Instance 1**: http://40.81.240.134:4000
- **LiteLLM Instance 2**: http://40.81.240.134:4001  
- **LiteLLM Instance 3**: http://40.81.240.134:4002
- **PostgreSQL**: localhost:5433 (internal to server)

### 🔧 **Dynamic Features**
- ✅ **Auto-conflict resolution**: Container names increment if conflicts exist
- ✅ **Dynamic port allocation**: Ports auto-increment from base port
- ✅ **Database consistency**: All instances share the same PostgreSQL database
- ✅ **Health monitoring**: Built-in health checks for all components
- ✅ **Easy scaling**: Deploy unlimited instances with one command

### 🛠️ **Troubleshooting**

#### **If Migration Fails**
```bash
# Check LiteLLM container logs
docker logs <litellm-container-name>

# Check PostgreSQL logs  
docker logs postgres-litellm

# Verify backup files
ls -la ./litellm_backup/
```

#### **If Load Distribution Issues**
```bash
# Check all containers
docker ps | grep -E "(litellm|postgres)"

# Test individual instances
curl http://localhost:4000/health
curl http://localhost:4001/health
curl http://localhost:4002/health

# Check database connectivity
docker exec postgres-litellm psql -U litellm_user -d litellm_db -c "\dt"
```

### 🎯 **Success Criteria**
1. **PostgreSQL Migration**: ✅ All data migrated to "postgres_litellm" 
2. **Schema Integrity**: ✅ All tables and records preserved
3. **Load Distribution**: ✅ Multiple LiteLLM instances running
4. **Database Sharing**: ✅ All instances use shared PostgreSQL
5. **Health Verification**: ✅ All endpoints responding
6. **Consistency**: ✅ Data consistent across all instances

**Your LiteLLM AI startup platform will be ready for enterprise-scale load distribution!** 🚀