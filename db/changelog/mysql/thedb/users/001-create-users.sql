--liquibase formatted sql

--changeset db-admin:101
--comment: Create read-write user for application
CREATE USER IF NOT EXISTS 'app_readwrite'@'%' IDENTIFIED BY 'CHANGE_ME_TEMP_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON thedb.* TO 'app_readwrite'@'%';
GRANT EXECUTE ON thedb.* TO 'app_readwrite'@'%';
FLUSH PRIVILEGES;

--changeset db-admin:102
--comment: Create read-only user for reporting
CREATE USER IF NOT EXISTS 'app_readonly'@'%' IDENTIFIED BY 'CHANGE_ME_TEMP_PASSWORD';
GRANT SELECT ON thedb.* TO 'app_readonly'@'%';
FLUSH PRIVILEGES;
