#!/usr/bin/env python3
"""
OpenWebUI SQLite to PostgreSQL Migration Script
Based on the research from GitHub discussions and Medium articles.
Customized for your AI startup setup.
"""

import sqlite3
import psycopg2
import traceback
import sys
import os
from datetime import datetime

# Configuration for Azure PostgreSQL
SQLITE_DB_PATH = 'webui_backup.db'  # Will be downloaded from Azure
BATCH_SIZE = 500
MAX_RETRIES = 3

# Azure PostgreSQL Configuration
PG_CONFIG = {
    'host': '40.81.240.134',
    'port': 5432,
    'database': 'openwebui_db',  # New dedicated database
    'user': 'litellm_user',
    'password': 'litellm_password'
}

def log_message(message):
    """Print message with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")

def check_sqlite_integrity():
    """Run integrity check on SQLite database"""
    log_message("Running SQLite database integrity check...")
    try:
        conn = sqlite3.connect(SQLITE_DB_PATH)
        cursor = conn.cursor()

        cursor.execute("PRAGMA integrity_check;")
        result = cursor.fetchall()

        cursor.execute("PRAGMA quick_check;")
        quick_result = cursor.fetchall()

        cursor.execute("PRAGMA foreign_key_check;")
        fk_result = cursor.fetchall()

        if result != [('ok',)]:
            log_message("❌ Database integrity check failed!")
            log_message(f"Integrity check results: {result}")
            return False

        if quick_result != [('ok',)]:
            log_message("❌ Quick check failed!")
            log_message(f"Quick check results: {quick_result}")
            return False

        if fk_result:
            log_message("❌ Foreign key check failed!")
            log_message(f"Foreign key issues: {fk_result}")
            return False

        try:
            cursor.execute("SELECT COUNT(*) FROM sqlite_master;")
            cursor.fetchone()
        except sqlite3.DatabaseError as e:
            log_message(f"❌ Database appears to be corrupted: {e}")
            return False

        log_message("✅ SQLite database integrity check passed")
        return True

    except Exception as e:
        log_message(f"❌ Error during integrity check: {e}")
        return False
    finally:
        if 'cursor' in locals():
            cursor.close()
        if 'conn' in locals():
            conn.close()

def sqlite_to_pg_type(sqlite_type: str) -> str:
    """Convert SQLite types to PostgreSQL types"""
    types = {
        'INTEGER': 'INTEGER',
        'REAL': 'DOUBLE PRECISION',
        'TEXT': 'TEXT',
        'BLOB': 'BYTEA',
        'NUMERIC': 'NUMERIC',
        'BOOLEAN': 'BOOLEAN',
        'DATETIME': 'TIMESTAMP',
        'DATE': 'DATE',
        'TIME': 'TIME'
    }
    return types.get(sqlite_type.upper(), 'TEXT')

def get_sqlite_safe_identifier(identifier: str) -> str:
    """Quotes identifiers for SQLite queries"""
    return f'"{identifier}"'

def get_pg_safe_identifier(identifier: str) -> str:
    """Quotes identifiers for PostgreSQL if they're reserved words"""
    reserved_keywords = {
        'user', 'group', 'order', 'table', 'select', 'where', 'from', 
        'index', 'constraint', 'function', 'procedure', 'trigger', 'view',
        'schema', 'database', 'column', 'primary', 'foreign', 'key',
        'references', 'unique', 'check', 'default', 'null', 'not'
    }
    return f'"{identifier}"' if identifier.lower() in reserved_keywords else identifier

def download_sqlite_db():
    """Download SQLite database from Azure server"""
    log_message("Downloading SQLite database from Azure server...")
    try:
        import subprocess
        # Use SSH to copy the database file
        cmd = [
            'ssh', '-i', 'runaii-chat-dev-server-1.pem', 
            '-o', 'StrictHostKeyChecking=no',
            'azureuser@40.81.240.134',
            'sudo docker cp runaii-openwebui:/app/backend/data/webui.db /tmp/webui_backup.db'
        ]
        subprocess.run(cmd, check=True, capture_output=True)
        
        # Download to local machine
        cmd = [
            'scp', '-i', 'runaii-chat-dev-server-1.pem',
            '-o', 'StrictHostKeyChecking=no',
            'azureuser@40.81.240.134:/tmp/webui_backup.db',
            'webui_backup.db'
        ]
        subprocess.run(cmd, check=True, capture_output=True)
        
        log_message("✅ SQLite database downloaded successfully")
        return True
    except Exception as e:
        log_message(f"❌ Failed to download SQLite database: {e}")
        return False

def migrate():
    """Main migration function"""
    # Download SQLite database first
    if not os.path.exists(SQLITE_DB_PATH):
        if not download_sqlite_db():
            log_message("Failed to download database. Exiting.")
            sys.exit(1)
    
    if not check_sqlite_integrity():
        log_message("Aborting migration due to database integrity issues")
        sys.exit(1)

    log_message("Starting OpenWebUI migration process...")
    log_message(f"Source: SQLite database ({SQLITE_DB_PATH})")
    log_message(f"Target: PostgreSQL at {PG_CONFIG['host']}:{PG_CONFIG['port']}/{PG_CONFIG['database']}")

    sqlite_conn = sqlite3.connect(SQLITE_DB_PATH, timeout=60)
    sqlite_cursor = sqlite_conn.cursor()

    # Optimize SQLite performance
    sqlite_cursor.execute('PRAGMA journal_mode=WAL')
    sqlite_cursor.execute('PRAGMA synchronous=NORMAL')

    pg_conn = psycopg2.connect(**PG_CONFIG)
    pg_cursor = pg_conn.cursor()

    total_migrated_rows = 0
    total_failed_rows = 0

    try:
        # Get all tables from SQLite
        sqlite_cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = sqlite_cursor.fetchall()

        log_message(f"Found {len(tables)} tables to migrate")

        for (table_name,) in tables:
            # Skip migration history and version tables
            if table_name.lower() in ("migratehistory", "alembic_version", "sqlite_sequence"):
                log_message(f"⏭️  Skipping system table: {table_name}")
                continue

            pg_safe_table_name = get_pg_safe_identifier(table_name)
            sqlite_safe_table_name = get_sqlite_safe_identifier(table_name)
            log_message(f"📋 Processing table: {table_name}")

            try:
                # First, let OpenWebUI create the schema by trying to connect
                log_message(f"Ensuring table {table_name} exists in PostgreSQL...")
                
                # Get table schema from SQLite
                retry_count = 0
                while retry_count < MAX_RETRIES:
                    try:
                        sqlite_cursor.execute(f'PRAGMA table_info({sqlite_safe_table_name})')
                        schema = sqlite_cursor.fetchall()
                        break
                    except sqlite3.DatabaseError as e:
                        retry_count += 1
                        log_message(f"Retry {retry_count}/{MAX_RETRIES} getting schema for {table_name}: {e}")
                        if retry_count == MAX_RETRIES:
                            raise

                if not schema:
                    log_message(f"⚠️  No schema found for table {table_name}, skipping")
                    continue

                # Check if table exists in PostgreSQL
                try:
                    pg_cursor.execute("""
                        SELECT EXISTS (
                            SELECT FROM information_schema.tables 
                            WHERE table_name = %s
                        )
                    """, (table_name,))
                    table_exists = pg_cursor.fetchone()[0]
                    
                    if not table_exists:
                        # Create table in PostgreSQL
                        columns = []
                        for col in schema:
                            col_name = get_pg_safe_identifier(col[1])
                            col_type = sqlite_to_pg_type(col[2])
                            nullable = "NOT NULL" if col[3] else ""
                            primary_key = "PRIMARY KEY" if col[5] else ""
                            
                            column_def = f"{col_name} {col_type} {nullable} {primary_key}".strip()
                            columns.append(column_def)
                        
                        create_query = f"CREATE TABLE IF NOT EXISTS {pg_safe_table_name} ({', '.join(columns)})"
                        log_message(f"Creating table: {table_name}")
                        pg_cursor.execute(create_query)
                        pg_conn.commit()
                    
                except psycopg2.Error as e:
                    log_message(f"⚠️  Could not verify/create table {table_name}: {e}")

                # Get column information from PostgreSQL
                try:
                    pg_cursor.execute("""
                        SELECT column_name, data_type
                        FROM information_schema.columns
                        WHERE table_name = %s
                        ORDER BY ordinal_position
                    """, (table_name,))
                    pg_columns = dict(pg_cursor.fetchall())
                except psycopg2.Error:
                    pg_columns = {}

                # Clear existing data
                try:
                    log_message(f"Clearing existing data from {table_name}")
                    pg_cursor.execute(f"TRUNCATE TABLE {pg_safe_table_name} CASCADE")
                    pg_conn.commit()
                except psycopg2.Error as e:
                    log_message(f"Note: Could not truncate {table_name}: {e}")

                # Migrate data
                log_message(f"🔄 Migrating data for table: {table_name}")

                sqlite_cursor.execute(f"SELECT COUNT(*) FROM {sqlite_safe_table_name}")
                total_rows = sqlite_cursor.fetchone()[0]
                processed_rows = 0
                failed_rows = []

                if total_rows == 0:
                    log_message(f"ℹ️  Table {table_name} is empty, skipping data migration")
                    continue

                log_message(f"Found {total_rows} rows to migrate")

                # Process data in batches
                while processed_rows < total_rows:
                    try:
                        sqlite_cursor.execute(f"""
                            SELECT * FROM {sqlite_safe_table_name} 
                            LIMIT {BATCH_SIZE} OFFSET {processed_rows}
                        """)
                        raw_rows = sqlite_cursor.fetchall()

                        if not raw_rows:
                            break

                        # Clean and process each row
                        for row_idx, raw_row in enumerate(raw_rows):
                            try:
                                # Clean the data
                                cleaned_row = []
                                for item in raw_row:
                                    if isinstance(item, bytes):
                                        try:
                                            cleaned_row.append(item.decode('utf-8', errors='replace'))
                                        except:
                                            cleaned_row.append(item.decode('latin1', errors='replace'))
                                    elif isinstance(item, str):
                                        # Handle special characters and null bytes
                                        cleaned_item = item.replace('\x00', '')
                                        cleaned_row.append(cleaned_item)
                                    else:
                                        cleaned_row.append(item)

                                # Prepare insert statement
                                col_names = [get_pg_safe_identifier(col[1]) for col in schema]
                                placeholders = ', '.join(['%s'] * len(cleaned_row))
                                
                                insert_query = f"""
                                    INSERT INTO {pg_safe_table_name} 
                                    ({', '.join(col_names)}) 
                                    VALUES ({placeholders})
                                """
                                
                                # Execute insert
                                pg_cursor.execute(insert_query, cleaned_row)
                                
                            except Exception as e:
                                error_msg = f"Row {processed_rows + row_idx}: {str(e)[:100]}"
                                failed_rows.append(error_msg)
                                log_message(f"❌ Error processing row in {table_name}: {error_msg}")
                                continue

                        processed_rows += len(raw_rows)
                        pg_conn.commit()
                        
                        # Progress update
                        progress = (processed_rows / total_rows) * 100
                        log_message(f"Progress: {processed_rows}/{total_rows} rows ({progress:.1f}%)")

                    except sqlite3.DatabaseError as e:
                        log_message(f"SQLite error during batch processing: {e}")
                        processed_rows += BATCH_SIZE
                        continue

                successful_rows = processed_rows - len(failed_rows)
                total_migrated_rows += successful_rows
                total_failed_rows += len(failed_rows)

                log_message(f"✅ Completed table {table_name}: {successful_rows}/{total_rows} rows migrated")
                
                if failed_rows:
                    log_message(f"⚠️  Failed rows in {table_name}: {len(failed_rows)}")
                    for error in failed_rows[:5]:  # Show first 5 errors
                        log_message(f"   - {error}")
                    if len(failed_rows) > 5:
                        log_message(f"   ... and {len(failed_rows) - 5} more errors")

            except Exception as e:
                log_message(f"❌ Critical error processing table {table_name}: {e}")
                traceback.print_exc()
                continue

        # Final summary
        log_message("\n" + "="*60)
        log_message("🎉 MIGRATION COMPLETED!")
        log_message(f"📊 Total rows migrated: {total_migrated_rows}")
        log_message(f"❌ Total failed rows: {total_failed_rows}")
        log_message(f"📋 Tables processed: {len([t for t in tables if t[0].lower() not in ('migratehistory', 'alembic_version', 'sqlite_sequence')])}")
        log_message("="*60)

        if total_failed_rows > 0:
            log_message(f"⚠️  Warning: {total_failed_rows} rows failed to migrate. Check logs above for details.")

        return total_failed_rows == 0

    except Exception as e:
        log_message(f"❌ Critical error during migration: {e}")
        traceback.print_exc()
        pg_conn.rollback()
        return False

    finally:
        # Cleanup connections
        if 'sqlite_cursor' in locals():
            sqlite_cursor.close()
        if 'sqlite_conn' in locals():
            sqlite_conn.close()
        if 'pg_cursor' in locals():
            pg_cursor.close()
        if 'pg_conn' in locals():
            pg_conn.close()
        
        log_message("🔌 Database connections closed")

if __name__ == "__main__":
    log_message("🚀 Starting OpenWebUI Migration for AI Startup")
    log_message("This will migrate your OpenWebUI data to PostgreSQL")
    log_message("="*60)
    
    try:
        success = migrate()
        if success:
            log_message("🎉 Migration completed successfully!")
            log_message("Next steps:")
            log_message("1. Configure OpenWebUI to use PostgreSQL")
            log_message("2. Start OpenWebUI with new database")
            log_message("3. Verify all data is accessible")
        else:
            log_message("❌ Migration completed with errors. Please review the logs.")
            sys.exit(1)
    except KeyboardInterrupt:
        log_message("\n⚠️  Migration interrupted by user")
        sys.exit(1)
    except Exception as e:
        log_message(f"❌ Fatal error: {e}")
        traceback.print_exc()
        sys.exit(1)