--liquibase formatted sql

--changeset sqlserver-team:001-create-reports-table
--comment: Create reports table for business intelligence
CREATE TABLE reports (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    report_name NVARCHAR(255) NOT NULL,
    report_type NVARCHAR(50) NOT NULL,
    parameters NVARCHAR(MAX),
    schedule_cron NVARCHAR(100),
    is_active BIT DEFAULT 1,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    updated_at DATETIME2 DEFAULT GETUTCDATE(),
    CONSTRAINT UK_reports_name UNIQUE (report_name)
);

--changeset sqlserver-team:001-create-report-executions-table
--comment: Create report executions tracking table
CREATE TABLE report_executions (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    report_id BIGINT NOT NULL,
    execution_status NVARCHAR(20) DEFAULT 'pending',
    started_at DATETIME2 DEFAULT GETUTCDATE(),
    completed_at DATETIME2 NULL,
    error_message NVARCHAR(MAX) NULL,
    result_file_path NVARCHAR(500) NULL,
    row_count INT NULL,
    FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
);

--changeset sqlserver-team:001-create-dashboards-table
--comment: Create dashboards table
CREATE TABLE dashboards (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    dashboard_name NVARCHAR(255) NOT NULL,
    layout_config NVARCHAR(MAX),
    is_public BIT DEFAULT 0,
    owner_user_id BIGINT,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    updated_at DATETIME2 DEFAULT GETUTCDATE(),
    CONSTRAINT UK_dashboards_name UNIQUE (dashboard_name)
);

--changeset sqlserver-team:001-create-indexes
--comment: Create performance indexes
CREATE NONCLUSTERED INDEX IX_report_executions_report_id ON report_executions(report_id);
CREATE NONCLUSTERED INDEX IX_report_executions_status ON report_executions(execution_status);
CREATE NONCLUSTERED INDEX IX_report_executions_started_at ON report_executions(started_at);