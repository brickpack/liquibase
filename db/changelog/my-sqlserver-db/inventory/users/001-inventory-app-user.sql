--liquibase formatted sql

--changeset DM-9001:001
--comment: Create inventory_app login for SQL Server
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.sql_logins WHERE name = 'inventory_app'
-- Note: Password will be set separately by manage-users.sh script
CREATE LOGIN inventory_app WITH PASSWORD = 'TemporaryPassword123!';

--changeset DM-9002:002
--comment: Create inventory_app database user
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'inventory_app'
CREATE USER inventory_app FOR LOGIN inventory_app;

--changeset DM-9003:003
--comment: Grant database role membership to inventory_app
--runOnChange:true
-- Grant db_datareader and db_datawriter roles for basic read/write access
ALTER ROLE db_datareader ADD MEMBER inventory_app;
ALTER ROLE db_datawriter ADD MEMBER inventory_app;

--changeset DM-9004:004
--comment: Grant additional permissions to inventory_app
--runOnChange:true
-- Grant EXECUTE for stored procedures
GRANT EXECUTE TO inventory_app;

-- Grant VIEW DEFINITION to see object metadata
GRANT VIEW DEFINITION TO inventory_app;

--changeset DM-9005:005
--comment: Grant table-specific permissions to inventory_app
--runOnChange:true
-- Grant SELECT, INSERT, UPDATE, DELETE on all tables in dbo schema
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO inventory_app;
