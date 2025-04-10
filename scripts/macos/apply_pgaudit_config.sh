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
PGAUDIT_CONFIG="scripts/macos/pgaudit_config.conf"
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