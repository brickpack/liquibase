--liquibase formatted sql

--changeset db-admin:107
--comment: Create invoice number sequence
IF NOT EXISTS (SELECT * FROM sys.sequences WHERE name = 'invoice_number_seq')
BEGIN
    CREATE SEQUENCE invoice_number_seq
        START WITH 1000
        INCREMENT BY 1
        MINVALUE 1000
        NO MAXVALUE
        CACHE 10;
END
GO

--changeset db-admin:108
--comment: Create tracking number sequence
IF NOT EXISTS (SELECT * FROM sys.sequences WHERE name = 'tracking_number_seq')
BEGIN
    CREATE SEQUENCE tracking_number_seq
        START WITH 100000
        INCREMENT BY 1
        MINVALUE 100000
        NO MAXVALUE
        CACHE 20;
END
GO
