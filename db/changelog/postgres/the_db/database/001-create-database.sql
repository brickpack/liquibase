--liquibase formatted sql

--changeset db-admin:000
--comment: Create the_db database
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_database WHERE datname = 'the_db'
CREATE DATABASE the_db;
