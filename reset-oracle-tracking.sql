--liquibase formatted sql

--changeset reset:drop-changelog-table
--comment: Reset Liquibase tracking to force re-deployment
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE DATABASECHANGELOG CASCADE CONSTRAINTS';
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF; -- Ignore table not found
END;
/

--changeset reset:drop-changeloglock-table
--comment: Reset Liquibase lock table
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE DATABASECHANGELOGLOCK CASCADE CONSTRAINTS';
    EXCEPTION WHEN OTHERS THEN
        IF SQLCODE != -942 THEN RAISE; END IF; -- Ignore table not found
END;
/