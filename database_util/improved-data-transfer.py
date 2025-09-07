#!/usr/bin/env python3
"""
Improved Data Transfer Script with Type Conversion
"""

import psycopg2
import sys
import json

# Configuration
PG_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'user': 'litellm_user',
    'password': 'litellm_password'
}

SOURCE_DB = 'openwebui_db'
TARGET_DB = 'openwebui_clean'

# Type conversion mappings for problematic columns
BOOLEAN_COLUMNS = {
    'auth': ['active'],
    'chat': ['archived', 'pinned'],
    'function': ['is_active', 'is_global'],
    'user': ['role', 'active']  # These might be booleans in new schema
}

def convert_value(table_name, column_name, value, target_type):
    """Convert values based on target type"""
    if target_type == 'boolean':
        if isinstance(value, int):
            return bool(value)
        elif isinstance(value, str):
            return value.lower() in ('true', '1', 'yes', 't')
        return bool(value)
    elif target_type in ['integer', 'bigint']:
        if value is None:
            return None
        return int(value) if str(value).isdigit() else None
    elif target_type.startswith('character varying') or target_type == 'text':
        if value is None:
            return None
        return str(value).replace('\x00', '')
    return value

def transfer_data():
    print("🔄 Starting improved data transfer with type conversion...")
    
    source_conn = psycopg2.connect(database=SOURCE_DB, **PG_CONFIG)
    target_conn = psycopg2.connect(database=TARGET_DB, **PG_CONFIG)
    
    source_cursor = source_conn.cursor()
    target_cursor = target_conn.cursor()
    
    try:
        # Get list of tables from target database (the clean one with proper schema)
        target_cursor.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
            AND table_name NOT IN ('alembic_version', 'migratehistory')
            ORDER BY table_name
        """)
        tables_to_transfer = [row[0] for row in target_cursor.fetchall()]
        
        for table_name in tables_to_transfer:
            print(f"📋 Processing table: {table_name}")
            
            try:
                # Check if table exists in source
                source_cursor.execute(f"SELECT to_regclass('public.{table_name}') IS NOT NULL")
                table_exists = source_cursor.fetchone()[0]
                
                if not table_exists:
                    print(f"⏭️  Table {table_name} doesn't exist in source, skipping")
                    continue
                
                # Get target table schema with data types
                target_cursor.execute(f"""
                    SELECT column_name, data_type, is_nullable
                    FROM information_schema.columns 
                    WHERE table_name = '{table_name}' 
                    AND table_schema = 'public'
                    ORDER BY ordinal_position
                """)
                target_schema = {row[0]: {'type': row[1], 'nullable': row[2]} for row in target_cursor.fetchall()}
                
                # Get source table columns
                source_cursor.execute(f"""
                    SELECT column_name 
                    FROM information_schema.columns 
                    WHERE table_name = '{table_name}' 
                    AND table_schema = 'public'
                    ORDER BY ordinal_position
                """)
                source_columns = [row[0] for row in source_cursor.fetchall()]
                
                # Find common columns
                common_columns = [col for col in target_schema.keys() if col in source_columns]
                
                if not common_columns:
                    print(f"⚠️  No common columns found for {table_name}")
                    continue
                
                # Clear target table
                target_cursor.execute(f'DELETE FROM "{table_name}"')
                target_conn.commit()
                
                # Get data from source
                columns_str = ', '.join([f'"{col}"' for col in common_columns])
                source_cursor.execute(f'SELECT {columns_str} FROM "{table_name}"')
                rows = source_cursor.fetchall()
                
                if not rows:
                    print(f"ℹ️  Table {table_name} is empty")
                    continue
                
                # Insert with type conversion
                placeholders = ', '.join(['%s'] * len(common_columns))
                insert_query = f'INSERT INTO "{table_name}" ({columns_str}) VALUES ({placeholders})'
                
                success_count = 0
                for row in rows:
                    try:
                        # Convert values based on target schema
                        converted_row = []
                        for i, (col_name, value) in enumerate(zip(common_columns, row)):
                            target_type = target_schema[col_name]['type']
                            converted_value = convert_value(table_name, col_name, value, target_type)
                            converted_row.append(converted_value)
                        
                        target_cursor.execute(insert_query, converted_row)
                        success_count += 1
                        
                    except Exception as e:
                        print(f"❌ Error inserting row in {table_name}: {e}")
                        target_conn.rollback()  # Rollback this transaction
                        continue
                
                target_conn.commit()
                print(f"✅ Transferred {success_count}/{len(rows)} rows for table: {table_name}")
                
            except Exception as e:
                print(f"❌ Error processing table {table_name}: {e}")
                target_conn.rollback()
                continue
        
        print("\n🎉 Improved data transfer completed!")
        return True
        
    except Exception as e:
        print(f"❌ Critical error: {e}")
        return False
    finally:
        source_cursor.close()
        source_conn.close()
        target_cursor.close()
        target_conn.close()

if __name__ == "__main__":
    success = transfer_data()
    sys.exit(0 if success else 1)