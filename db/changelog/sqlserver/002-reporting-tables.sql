--liquibase formatted sql

--changeset sqlserver-team:002-create-report-subscriptions-table
--comment: Create report subscriptions for automated delivery
CREATE TABLE report_subscriptions (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    report_id BIGINT NOT NULL,
    subscriber_email NVARCHAR(320) NOT NULL,
    delivery_format NVARCHAR(20) DEFAULT 'PDF',
    delivery_schedule NVARCHAR(100),
    is_active BIT DEFAULT 1,
    last_delivered DATETIME2 NULL,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT chk_delivery_format CHECK (delivery_format IN ('PDF', 'EXCEL', 'CSV', 'JSON'))
);

--changeset sqlserver-team:002-create-data-sources-table
--comment: Create data sources configuration table
CREATE TABLE data_sources (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_name NVARCHAR(255) NOT NULL,
    connection_string NVARCHAR(1000),
    source_type NVARCHAR(50) NOT NULL,
    is_active BIT DEFAULT 1,
    last_tested DATETIME2 NULL,
    test_status NVARCHAR(20) DEFAULT 'UNKNOWN',
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    updated_at DATETIME2 DEFAULT GETUTCDATE(),
    CONSTRAINT UK_data_sources_name UNIQUE (source_name),
    CONSTRAINT chk_source_type CHECK (source_type IN ('SQL_SERVER', 'POSTGRESQL', 'MYSQL', 'ORACLE', 'API', 'FILE'))
);

--changeset sqlserver-team:002-create-report-data-sources-table
--comment: Create many-to-many relationship between reports and data sources
CREATE TABLE report_data_sources (
    report_id BIGINT NOT NULL,
    data_source_id BIGINT NOT NULL,
    PRIMARY KEY (report_id, data_source_id),
    FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE
);