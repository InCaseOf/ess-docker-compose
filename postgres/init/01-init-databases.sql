-- Create additional databases for Matrix Authentication Service and Authelia
-- Create additional databases for Matrix Authentication Service
-- The main 'synapse' database is already created via POSTGRES_DB env var

-- Create database for Matrix Authentication Service (MAS)
CREATE DATABASE mas;

-- Create database for Sliding Sync Proxy
CREATE DATABASE syncv3;

-- Grant privileges to the synapse user for all databases
GRANT ALL PRIVILEGES ON DATABASE mas TO synapse;
GRANT ALL PRIVILEGES ON DATABASE syncv3 TO synapse;

-- Display confirmation
\echo 'Additional databases created: mas, syncv3'
