--liquibase formatted sql

--changeset admin:001-create-analytics-database dbms:postgresql
--comment: Create analytics database if it doesn't exist
--runOnChange:true
--labels:bootstrap
--preconditions onFail:CONTINUE
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_database WHERE datname = 'analytics'
CREATE DATABASE analytics;

--changeset admin:001-create-reporting-database dbms:postgresql
--comment: Create reporting database if it doesn't exist
--runOnChange:true
--labels:bootstrap
--preconditions onFail:CONTINUE
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_database WHERE datname = 'reporting'
CREATE DATABASE reporting;

--changeset admin:001-create-warehouse-database dbms:postgresql
--comment: Create data warehouse database if it doesn't exist
--runOnChange:true
--labels:bootstrap
--preconditions onFail:CONTINUE
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM pg_database WHERE datname = 'warehouse'
CREATE DATABASE warehouse;