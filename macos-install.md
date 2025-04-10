# Installing pgAudit on macOS (Apple Silicon)

This guide provides instructions for installing pgAudit on macOS, specifically for Apple Silicon (M1/M2/M3) systems running PostgreSQL 16 installed through the EnterpriseDB installer.

## Prerequisites

- PostgreSQL 16 installed via the EnterpriseDB installer
- Xcode Command Line Tools installed
- Git

## Compilation Issues on macOS

PostgreSQL extensions on macOS, particularly on Apple Silicon machines, can encounter several challenges:

1. **SDK Mismatch**: The PostgreSQL binary is often compiled with a specific macOS SDK version that may differ from what's available on your system.
2. **Architecture Issues**: When compiling for arm64 (Apple Silicon) architecture, compatibility issues may arise if PostgreSQL was compiled for Universal Binary (x86_64 + arm64).
3. **Library Path Issues**: The search paths for libraries may not align with your system configuration.

## Installation Script

Below is a custom script designed to compile pgAudit on macOS with Apple Silicon processors. Save it to a file called `build_pgaudit_macos.sh`:

```bash
#!/bin/bash
# Script to compile pgAudit for PostgreSQL 16 on macOS (Apple Silicon)

set -e

# Verify if the directory already exists
if [ ! -d "/tmp/pgaudit" ]; then
  # Clone the pgAudit repository
  echo "Cloning pgAudit repository..."
  mkdir -p /tmp/pgaudit
  cd /tmp/pgaudit
  git clone https://github.com/pgaudit/pgaudit.git .
  git checkout REL_16_STABLE
else
  cd /tmp/pgaudit
  git checkout REL_16_STABLE
fi

# Get PostgreSQL configuration information
PG_CONFIG=/Library/PostgreSQL/16/bin/pg_config
PG_INCLUDEDIR=$($PG_CONFIG --includedir)
PG_PKGLIBDIR=$($PG_CONFIG --pkglibdir)
PG_SHAREDIR=$($PG_CONFIG --sharedir)
PG_CFLAGS=$($PG_CONFIG --cflags)
PG_CPPFLAGS=$($PG_CONFIG --cppflags)
PG_LDFLAGS=$($PG_CONFIG --ldflags)

# Configure to use the available SDK
# Find the latest available SDK
SDK_PATH=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk | sort -V | tail -n 1)

echo "Compiling pgAudit with the following options:"
echo "PG_INCLUDEDIR: $PG_INCLUDEDIR"
echo "PG_PKGLIBDIR: $PG_PKGLIBDIR"
echo "SDK_PATH: $SDK_PATH"

# Compile pgAudit
echo "Compiling pgAudit..."
make clean || true
make USE_PGXS=1 PG_CONFIG=$PG_CONFIG CFLAGS="$PG_CFLAGS -isysroot $SDK_PATH" CPPFLAGS="$PG_CPPFLAGS -isysroot $SDK_PATH" LDFLAGS="$PG_LDFLAGS -isysroot $SDK_PATH"

# Install pgAudit
echo "Installing pgAudit..."
sudo make install USE_PGXS=1 PG_CONFIG=$PG_CONFIG

# Verify if the module was installed correctly
if [ -f "$PG_PKGLIBDIR/pgaudit.so" ] || [ -f "$PG_PKGLIBDIR/pgaudit.dylib" ]; then
  echo "pgAudit module successfully installed in $PG_PKGLIBDIR"
else
  echo "Error: pgAudit module not installed!"
  exit 1
fi

# Create the control file if it doesn't already exist
CONTROL_FILE="$PG_SHAREDIR/extension/pgaudit.control"
if [ ! -f "$CONTROL_FILE" ]; then
  echo "Creating pgaudit.control file..."
  sudo bash -c "cat > $CONTROL_FILE << EOF
# pgAudit extension
comment = 'PostgreSQL Audit Extension'
default_version = '16.0'
module_pathname = '\$libdir/pgaudit'
relocatable = false
trusted = true
EOF"
fi

# Verify if the control file was installed correctly
if [ -f "$CONTROL_FILE" ]; then
  echo "pgaudit.control file successfully installed in $PG_SHAREDIR/extension"
else
  echo "Error: pgaudit.control file not installed!"
  exit 1
fi

# Check SQL files
SQL_DIR="$PG_SHAREDIR/extension"
if [ -f "$SQL_DIR/pgaudit--16.0.sql" ] || [ -f "$SQL_DIR/pgaudit--16.1.sql" ]; then
  echo "pgAudit SQL files found in $SQL_DIR"
else
  echo "Warning: No pgAudit SQL files found in $SQL_DIR"
  
  # Create basic SQL files if needed
  if [ ! -f "$SQL_DIR/pgaudit--16.0.sql" ]; then
    echo "Creating a basic SQL file for pgAudit 16.0..."
    sudo bash -c "cat > $SQL_DIR/pgaudit--16.0.sql << EOF
-- complains if script is sourced in psql, since it's not inside a transaction
\\echo Use \"CREATE EXTENSION pgaudit\" to load this file. \\quit

-- Empty SQL file for pgAudit 16.0
EOF"
  fi
fi

echo "pgAudit installation complete!"
```

## Configuration

Create a configuration file to enable pgAudit in PostgreSQL. Save it to a file called `pgaudit_config.conf`:

```
# Configuration for pgAudit

# Load pgAudit
shared_preload_libraries = 'pgaudit'

# Audit configuration
pgaudit.log = 'ddl, write'       # Audit DDL and write operations (INSERT, UPDATE, DELETE)
pgaudit.log_catalog = on         # Audit catalog objects
pgaudit.log_parameter = on       # Include query parameters
pgaudit.log_statement_once = on  # Log the statement text only once
pgaudit.log_level = 'log'        # Log level
pgaudit.log_relation = on        # Log all relations referenced in queries

# Logging configuration
logging_collector = on                # Enable log collection
log_directory = 'pg_log'              # Log directory
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log' # Log filename format
log_line_prefix = '%m [%p] %q%u@%d ' # Log line prefix format
log_statement = 'none'                # Disable standard query logging (pgAudit will handle it)
```

## Application Script

Create a script to apply the configuration and restart PostgreSQL. Save it to a file called `apply_pgaudit_config.sh`:

```bash
#!/bin/bash
# Script to apply pgAudit configuration and restart PostgreSQL

set -e

# Check for sudo privileges
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo"
  exit 1
fi

# Paths
PG_DATA="/Library/PostgreSQL/16/data"
PG_CONFIG_FILE="$PG_DATA/postgresql.conf"
PGAUDIT_CONFIG="pgaudit_config.conf"
BACKUP_SUFFIX=".$(date +%Y%m%d%H%M%S).bak"

# Verify pgAudit is installed
if [ ! -f "/Library/PostgreSQL/16/lib/postgresql/pgaudit.dylib" ] && [ ! -f "/Library/PostgreSQL/16/lib/postgresql/pgaudit.so" ]; then
  echo "Error: pgAudit is not installed. Please run the build_pgaudit_macos.sh script first."
  exit 1
fi

# Backup the configuration file
echo "Backing up PostgreSQL configuration..."
cp "$PG_CONFIG_FILE" "$PG_CONFIG_FILE$BACKUP_SUFFIX"
echo "Backup created: $PG_CONFIG_FILE$BACKUP_SUFFIX"

# Add pgAudit configurations
echo "Adding pgAudit configurations..."
cat "$PGAUDIT_CONFIG" >> "$PG_CONFIG_FILE"
echo "pgAudit configuration added to $PG_CONFIG_FILE"

# Create log directory if needed
PG_LOG_DIR="$PG_DATA/pg_log"
if [ ! -d "$PG_LOG_DIR" ]; then
  echo "Creating log directory..."
  mkdir -p "$PG_LOG_DIR"
  chown postgres:postgres "$PG_LOG_DIR"
  chmod 700 "$PG_LOG_DIR"
fi

# Restart PostgreSQL
echo "Restarting PostgreSQL..."
/Library/PostgreSQL/16/bin/pg_ctl restart -D "$PG_DATA" -m fast

# Check if PostgreSQL started successfully
sleep 2
if /Library/PostgreSQL/16/bin/pg_isready -q; then
  echo "PostgreSQL successfully restarted with pgAudit configuration!"
  echo "You can check audit logs in $PG_LOG_DIR"
else
  echo "Error: PostgreSQL failed to start correctly."
  echo "Restoring previous configuration..."
  cp "$PG_CONFIG_FILE$BACKUP_SUFFIX" "$PG_CONFIG_FILE"
  /Library/PostgreSQL/16/bin/pg_ctl restart -D "$PG_DATA" -m fast
  echo "Configuration restored and PostgreSQL restarted."
  exit 1
fi
```

## Test Script

To test pgAudit functionality, create a SQL script called `test_pgaudit.sql`:

```sql
-- Script to test pgAudit
-- Execute with: psql -U postgres -f test_pgaudit.sql

-- Check if pgaudit extension is available
SELECT * FROM pg_available_extensions WHERE name = 'pgaudit';

-- Create a test database
DROP DATABASE IF EXISTS audit_test;
CREATE DATABASE audit_test;

\connect audit_test

-- Enable pgaudit extension
CREATE EXTENSION IF NOT EXISTS pgaudit;

-- Create a test user
DROP ROLE IF EXISTS audit_test_user;
CREATE ROLE audit_test_user WITH LOGIN PASSWORD 'test123';

-- Create a test schema and table
CREATE SCHEMA audit_schema;
CREATE TABLE audit_schema.test_table (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO audit_schema.test_table (name) VALUES ('Test Record 1');
INSERT INTO audit_schema.test_table (name) VALUES ('Test Record 2');

-- Update data
UPDATE audit_schema.test_table SET name = 'Updated Record' WHERE id = 1;

-- Delete data
DELETE FROM audit_schema.test_table WHERE id = 2;

-- Grant privileges
GRANT USAGE ON SCHEMA audit_schema TO audit_test_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON audit_schema.test_table TO audit_test_user;

-- Message to verify logs
\echo 'Audit test complete. Check logs in the pg_log directory.'
```

## Log Verification Script

Create a script to verify audit logs called `check_audit_logs.sh`:

```bash
#!/bin/bash
# Script to verify pgAudit audit logs

# PostgreSQL log path
PG_LOG_DIR="/Library/PostgreSQL/16/data/pg_log"

# Check if log directory exists
if [ ! -d "$PG_LOG_DIR" ]; then
  echo "Error: Log directory $PG_LOG_DIR does not exist."
  exit 1
fi

# Find the most recent log file
LATEST_LOG=$(ls -t "$PG_LOG_DIR"/postgresql-*.log 2>/dev/null | head -1)

if [ -z "$LATEST_LOG" ]; then
  echo "Error: No log files found in $PG_LOG_DIR"
  exit 1
fi

echo "Examining log file: $LATEST_LOG"
echo "----------------------------------------"

# Display audit entries (pgaudit)
echo "pgAudit entries:"
echo "----------------------------------------"
grep -i "AUDIT:" "$LATEST_LOG" | tail -n 20

# Statistics
AUDIT_COUNT=$(grep -i "AUDIT:" "$LATEST_LOG" | wc -l)
echo ""
echo "Audit statistics:"
echo "----------------------------------------"
echo "Total audit entries: $AUDIT_COUNT"
echo ""

# Show different types of audited operations
echo "Types of audited operations:"
echo "----------------------------------------"
grep -i "AUDIT:" "$LATEST_LOG" | grep -o "STATEMENT: [A-Z]\+" | sort | uniq -c | sort -nr

echo ""
echo "Audit entries by user:"
echo "----------------------------------------"
grep -i "AUDIT:" "$LATEST_LOG" | grep -o "USER: [a-z_]\+" | sort | uniq -c | sort -nr
```

## Installation Steps

1. Make the scripts executable:
   ```bash
   chmod +x build_pgaudit_macos.sh
   chmod +x apply_pgaudit_config.sh
   chmod +x check_audit_logs.sh
   ```

2. Compile and install pgAudit:
   ```bash
   ./build_pgaudit_macos.sh
   ```

3. Apply the pgAudit configuration:
   ```bash
   sudo ./apply_pgaudit_config.sh
   ```

4. Test pgAudit:
   ```bash
   psql -U postgres -f test_pgaudit.sql
   ```

5. Check the audit logs:
   ```bash
   sudo ./check_audit_logs.sh
   ```

## Troubleshooting

### Common Issues

1. **Compilation Errors**:
   - Check that Xcode Command Line Tools are installed correctly
   - Verify the SDK path in the compilation script

2. **PostgreSQL Won't Start**:
   - Check the PostgreSQL error logs at `/Library/PostgreSQL/16/data/pg_log/`
   - The script will automatically restore the previous configuration if PostgreSQL fails to start

3. **pgAudit Not Logging**:
   - Verify that `shared_preload_libraries = 'pgaudit'` is correctly set in postgresql.conf
   - Confirm that the pgAudit extension is created in the database with `CREATE EXTENSION pgaudit`
   - Restart PostgreSQL if needed

4. **Architecture Mismatch**:
   - If you see warnings like "found architecture 'arm64', required architecture 'x86_64'", you may need to force a specific architecture during compilation

## Notes

This guide is specifically tailored for PostgreSQL 16 installed via the EnterpriseDB installer on macOS with Apple Silicon processors. The steps may vary for other versions or installation methods.

Always backup your PostgreSQL data and configuration before making changes to your setup.