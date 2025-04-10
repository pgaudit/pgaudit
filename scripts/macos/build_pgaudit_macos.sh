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