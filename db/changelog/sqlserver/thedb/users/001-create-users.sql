--liquibase formatted sql

--changeset db-admin:101
--comment: Create read-write user for application
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'app_readwrite')
BEGIN
    CREATE LOGIN app_readwrite WITH PASSWORD = 'CHANGE_ME_TEMP_PASSWORD';
END
GO

USE thedb;
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'app_readwrite')
BEGIN
    CREATE USER app_readwrite FOR LOGIN app_readwrite;
END
GO

ALTER ROLE db_datareader ADD MEMBER app_readwrite;
ALTER ROLE db_datawriter ADD MEMBER app_readwrite;
GRANT EXECUTE TO app_readwrite;
GO

--changeset db-admin:102
--comment: Create read-only user for reporting
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'app_readonly')
BEGIN
    CREATE LOGIN app_readonly WITH PASSWORD = 'CHANGE_ME_TEMP_PASSWORD';
END
GO

USE thedb;
GO

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'app_readonly')
BEGIN
    CREATE USER app_readonly FOR LOGIN app_readonly;
END
GO

ALTER ROLE db_datareader ADD MEMBER app_readonly;
GO
