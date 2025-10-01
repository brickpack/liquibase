--liquibase formatted sql

--changeset DM-3001:0.1.001
--comment: Create application users for myappdb
CREATE USER IF NOT EXISTS 'app_user'@'%' IDENTIFIED BY 'StrongPass123!';
CREATE USER IF NOT EXISTS 'report_user'@'%' IDENTIFIED BY 'ReportPass123!';

--changeset DM-3002:0.1.002
--comment: Grant privileges to application users
GRANT SELECT, INSERT, UPDATE, DELETE ON myappdb.* TO 'app_user'@'%';
GRANT SELECT ON myappdb.* TO 'report_user'@'%';

