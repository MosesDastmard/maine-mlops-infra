#!/bin/bash
# Post-installation configuration script for TimescaleDB
# This script creates the maine database and historical schema
#
# Run this after TimescaleDB is deployed if init scripts didn't execute

set -e

NAMESPACE="${TIMESCALEDB_NAMESPACE:-mlops-timescaledb}"
DB_USER="${DB_USER:-mlops}"
DB_NAME="${DB_NAME:-maine}"
SCHEMA_NAME="${SCHEMA_NAME:-historical}"

echo "Configuring TimescaleDB..."

# Wait for pod to be ready
echo "Waiting for TimescaleDB pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n "$NAMESPACE" --timeout=120s

POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

# Create database if not exists
echo "Creating database '$DB_NAME'..."
kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- psql -U "$DB_USER" -d postgres -c "
  SELECT 'Database already exists' WHERE EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')
  UNION ALL
  SELECT 'CREATE DATABASE $DB_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME');
" | grep -q "CREATE DATABASE" && \
kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- psql -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;" || \
echo "Database '$DB_NAME' already exists"

# Enable TimescaleDB extension and create schema
echo "Enabling TimescaleDB extension and creating schema '$SCHEMA_NAME'..."
kubectl exec -i "$POD_NAME" -n "$NAMESPACE" -- psql -U "$DB_USER" -d "$DB_NAME" <<EOF
-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Create schema for historical data
CREATE SCHEMA IF NOT EXISTS $SCHEMA_NAME;

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA $SCHEMA_NAME TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA $SCHEMA_NAME GRANT ALL PRIVILEGES ON TABLES TO $DB_USER;
EOF

echo "TimescaleDB configured successfully!"
echo "  - Database: $DB_NAME"
echo "  - Schema: $SCHEMA_NAME"
echo "  - Extension: timescaledb"
