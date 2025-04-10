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