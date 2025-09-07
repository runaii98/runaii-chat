#!/usr/bin/env python3
"""
Reset OpenWebUI Admin Password Script
"""

import psycopg2
import bcrypt
import sys

# Configuration
PG_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'openwebui_clean',
    'user': 'litellm_user',
    'password': 'litellm_password'
}

def reset_admin_password():
    print("🔑 Resetting OpenWebUI Admin Password...")
    
    # Set new password (you can change this)
    new_password = "admin123"
    admin_email = "shikhar@gameonn.cloud"
    
    try:
        # Generate bcrypt hash for new password
        password_hash = bcrypt.hashpw(new_password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        print(f"✅ Generated new password hash")
        
        # Connect to database
        conn = psycopg2.connect(**PG_CONFIG)
        cursor = conn.cursor()
        
        # Update password in auth table
        cursor.execute("""
            UPDATE "auth" 
            SET password = %s 
            WHERE email = %s
        """, (password_hash, admin_email))
        
        if cursor.rowcount > 0:
            conn.commit()
            print(f"✅ Password updated successfully for {admin_email}")
            print(f"🔐 New password: {new_password}")
            print(f"📧 Login email: {admin_email}")
            print(f"🌐 Access your OpenWebUI at: http://40.81.240.134:3001")
        else:
            print(f"❌ No user found with email: {admin_email}")
            
        cursor.close()
        conn.close()
        
        return True
        
    except Exception as e:
        print(f"❌ Error resetting password: {e}")
        return False

if __name__ == "__main__":
    success = reset_admin_password()
    sys.exit(0 if success else 1)