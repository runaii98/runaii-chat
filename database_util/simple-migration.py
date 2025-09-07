#!/usr/bin/env python3
"""
Simple OpenWebUI Migration Script to run on Azure server
"""

import sqlite3
import psycopg2
import sys
import os

# Configuration
SQLITE_DB_PATH = '/tmp/webui_backup.db'
PG_CONFIG = {
    'host': 'localhost',  # Running on same server
    'port': 5432,
    'database': 'openwebui_db',
    'user': 'litellm_user',
    'password': 'litellm_password'
}

def migrate_simple():
    print("🚀 Starting OpenWebUI Migration...")
    
    # Connect to databases
    sqlite_conn = sqlite3.connect(SQLITE_DB_PATH)
    sqlite_cursor = sqlite_conn.cursor()
    
    pg_conn = psycopg2.connect(**PG_CONFIG)
    pg_cursor = pg_conn.cursor()
    
    try:
        # Get all tables
        sqlite_cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = sqlite_cursor.fetchall()
        
        print(f"Found {len(tables)} tables to migrate")
        
        for (table_name,) in tables:
            if table_name.lower() in ("migratehistory", "alembic_version", "sqlite_sequence"):
                print(f"⏭️  Skipping system table: {table_name}")
                continue
            
            print(f"📋 Processing table: {table_name}")
            
            # Get table schema
            sqlite_cursor.execute(f'PRAGMA table_info("{table_name}")')
            schema = sqlite_cursor.fetchall()
            
            if not schema:
                continue
            
            # Create table in PostgreSQL (basic types)
            columns = []
            for col in schema:
                col_name = f'"{col[1]}"' if col[1].lower() in ['user', 'group', 'order'] else col[1]
                col_type = 'INTEGER' if 'INTEGER' in col[2].upper() else 'TEXT'
                columns.append(f"{col_name} {col_type}")
            
            try:
                create_query = f'CREATE TABLE IF NOT EXISTS "{table_name}" ({", ".join(columns)})'
                pg_cursor.execute(create_query)
                pg_conn.commit()
                print(f"✅ Created table: {table_name}")
            except Exception as e:
                print(f"⚠️  Table {table_name} might already exist: {e}")
            
            # Migrate data
            try:
                # Clear existing data
                pg_cursor.execute(f'DELETE FROM "{table_name}"')
                
                # Get data from SQLite
                sqlite_cursor.execute(f'SELECT * FROM "{table_name}"')
                rows = sqlite_cursor.fetchall()
                
                if not rows:
                    print(f"ℹ️  Table {table_name} is empty")
                    continue
                
                # Insert data
                col_names = [col[1] for col in schema]
                col_names_quoted = [f'"{name}"' if name.lower() in ['user', 'group', 'order'] else name for name in col_names]
                placeholders = ', '.join(['%s'] * len(col_names))
                
                insert_query = f'INSERT INTO "{table_name}" ({", ".join(col_names_quoted)}) VALUES ({placeholders})'
                
                for row in rows:
                    # Clean data
                    cleaned_row = []
                    for item in row:
                        if isinstance(item, str):
                            cleaned_row.append(item.replace('\x00', ''))
                        else:
                            cleaned_row.append(item)
                    
                    try:
                        pg_cursor.execute(insert_query, cleaned_row)
                    except Exception as e:
                        print(f"❌ Error inserting row: {e}")
                        continue
                
                pg_conn.commit()
                print(f"✅ Migrated {len(rows)} rows for table: {table_name}")
                
            except Exception as e:
                print(f"❌ Error migrating table {table_name}: {e}")
                continue
        
        print("\n🎉 Migration completed!")
        return True
        
    except Exception as e:
        print(f"❌ Critical error: {e}")
        return False
    finally:
        sqlite_cursor.close()
        sqlite_conn.close()
        pg_cursor.close()
        pg_conn.close()

if __name__ == "__main__":
    success = migrate_simple()
    sys.exit(0 if success else 1)