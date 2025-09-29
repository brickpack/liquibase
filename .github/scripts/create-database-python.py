#!/usr/bin/env python3
"""
Lightweight SQL Server database creation using Python and pyodbc.
This is much faster than installing the full mssql-tools package.
"""

import sys
import json
import pyodbc
import argparse

def create_database(host, port, username, password, database_name):
    """Create SQL Server database using pyodbc."""

    # Connection string for SQL Server with SSL bypass
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={host},{port};"
        f"UID={username};"
        f"PWD={password};"
        f"Encrypt=no;"
        f"TrustServerCertificate=yes;"
        f"DATABASE=master;"
    )

    print(f"🔗 Connecting to SQL Server: {host}:{port}")

    try:
        # Connect to master database
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()

        # Check if database exists
        cursor.execute("SELECT COUNT(*) FROM sys.databases WHERE name = ?", database_name)
        exists = cursor.fetchone()[0]

        if exists:
            print(f"ℹ️ Database {database_name} already exists, skipping creation")
        else:
            print(f"📝 Creating database {database_name}...")
            # Create database (can't use parameters for database name in CREATE DATABASE)
            cursor.execute(f"CREATE DATABASE [{database_name}] COLLATE SQL_Latin1_General_CP1_CI_AS")
            conn.commit()
            print(f"✅ Database {database_name} created successfully")

        cursor.close()
        conn.close()
        return True

    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Create SQL Server database')
    parser.add_argument('--host', required=True, help='SQL Server host')
    parser.add_argument('--port', required=True, help='SQL Server port')
    parser.add_argument('--username', required=True, help='Username')
    parser.add_argument('--password', required=True, help='Password')
    parser.add_argument('--database', required=True, help='Database name to create')

    args = parser.parse_args()

    success = create_database(args.host, args.port, args.username, args.password, args.database)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()