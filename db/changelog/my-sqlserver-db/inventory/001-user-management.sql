--liquibase formatted sql

--changeset myapp-team:001-create-app-user
--comment: Create application user for inventory database
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'app_user'
CREATE USER app_user WITH PASSWORD = 'StrongPass123!';

--changeset myapp-team:001-create-report-user
--comment: Create report user for inventory database
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = 'report_user'
CREATE USER report_user WITH PASSWORD = 'ReportPass123!';

--changeset myapp-team:001-grant-privileges
--comment: Grant privileges to application users
--runOnChange:true
-- Grant full access to app_user
ALTER ROLE db_datareader ADD MEMBER app_user;
ALTER ROLE db_datawriter ADD MEMBER app_user;
ALTER ROLE db_ddladmin ADD MEMBER app_user;

-- Grant read-only access to report_user
ALTER ROLE db_datareader ADD MEMBER report_user;

