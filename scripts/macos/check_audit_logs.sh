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