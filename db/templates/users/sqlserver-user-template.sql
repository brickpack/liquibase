--liquibase formatted sql

--changeset user-management:create-{{USERNAME}}-login
--comment: Create server login {{USERNAME}} for SQL Server
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.server_principals WHERE name = '{{USERNAME}}'
CREATE LOGIN [{{USERNAME}}] WITH
    PASSWORD = '{{PASSWORD:{{USERNAME}}}}',
    DEFAULT_DATABASE = [{{DATABASE_NAME}}],
    CHECK_EXPIRATION = OFF,
    CHECK_POLICY = ON;

--changeset user-management:create-{{USERNAME}}-user
--comment: Create database user {{USERNAME}} for SQL Server
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.database_principals WHERE name = '{{USERNAME}}'
CREATE USER [{{USERNAME}}] FOR LOGIN [{{USERNAME}}]
    WITH DEFAULT_SCHEMA = [{{DEFAULT_SCHEMA}}];

--changeset user-management:grant-{{USERNAME}}-privileges
--comment: Grant privileges to {{USERNAME}}
--runOnChange:true
-- Grant role memberships (customize based on role)
{{ROLE_MEMBERSHIPS}}

-- Grant specific permissions if needed
{{SPECIFIC_PERMISSIONS}}

--changeset user-management:create-{{USERNAME}}-comment
--comment: Add extended property for {{USERNAME}} user documentation
EXEC sys.sp_addextendedproperty
    @name = N'Description',
    @value = N'{{ROLE_DESCRIPTION}}',
    @level0type = N'SCHEMA',
    @level0name = N'{{DEFAULT_SCHEMA}}',
    @level1type = N'USER',
    @level1name = N'{{USERNAME}}';