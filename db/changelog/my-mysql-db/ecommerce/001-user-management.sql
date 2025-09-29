--liquibase formatted sql

--changeset myapp-team:001-create-app-users
--comment: Create application users for myappdb
CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED BY 'StrongPass123!';
CREATE USER IF NOT EXISTS 'report_user'@'%' IDENTIFIED BY 'ReportPass123!';

--changeset myapp-team:001-grant-privileges
--comment: Grant privileges to application users
GRANT SELECT, INSERT, UPDATE, DELETE ON myappdb.* TO 'app_user'@'%';
GRANT SELECT ON myappdb.* TO 'report_user'@'%';

