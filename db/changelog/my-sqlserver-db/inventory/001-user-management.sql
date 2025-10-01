--liquibase formatted sql

--changeset DM-4001:0.1.001
--comment: Create application login for SQL Server (server-level)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.server_principals WHERE name = 'app_user'
CREATE LOGIN app_user WITH PASSWORD = 'StrongPass123!';

--changeset DM-4002:0.1.002
--comment: Create application user for inventory database (database-level)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'app_user'
CREATE USER app_user FOR LOGIN app_user;

--changeset DM-4003:0.1.003
--comment: Create report login for SQL Server (server-level)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.server_principals WHERE name = 'report_user'
CREATE LOGIN report_user WITH PASSWORD = 'ReportPass123!';

--changeset DM-4004:0.1.004
--comment: Create report user for inventory database (database-level)
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'report_user'
CREATE USER report_user FOR LOGIN report_user;

--changeset DM-4005:0.1.005
--comment: Grant privileges to application users
--runOnChange:true
-- Grant full access to app_user
ALTER ROLE db_datareader ADD MEMBER app_user;
ALTER ROLE db_datawriter ADD MEMBER app_user;
ALTER ROLE db_ddladmin ADD MEMBER app_user;

-- Grant read-only access to report_user
ALTER ROLE db_datareader ADD MEMBER report_user;

