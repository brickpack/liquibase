--liquibase formatted sql

--changeset db-admin:007
--comment: Create invoice number sequence
CREATE SEQUENCE IF NOT EXISTS invoice_number_seq
    START WITH 1000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 10;

--changeset db-admin:008
--comment: Create tracking number sequence
CREATE SEQUENCE IF NOT EXISTS tracking_number_seq
    START WITH 100000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 20;
