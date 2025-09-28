--liquibase formatted sql

--changeset sqlserver-team:003-add-performance-indexes
--comment: Add performance indexes for reporting system
CREATE NONCLUSTERED INDEX IX_reports_type_active ON reports(report_type, is_active) INCLUDE (report_name);
CREATE NONCLUSTERED INDEX IX_report_executions_date_status ON report_executions(started_at, execution_status) INCLUDE (completed_at, row_count);
CREATE NONCLUSTERED INDEX IX_dashboards_owner_public ON dashboards(owner_user_id, is_public) INCLUDE (dashboard_name);
CREATE NONCLUSTERED INDEX IX_report_subscriptions_active_schedule ON report_subscriptions(is_active, delivery_schedule) INCLUDE (subscriber_email);

--changeset sqlserver-team:003-add-columnstore-indexes
--comment: Add columnstore indexes for analytics
CREATE NONCLUSTERED COLUMNSTORE INDEX NCCI_report_executions_analytics
ON report_executions (report_id, execution_status, started_at, completed_at, row_count);

--changeset sqlserver-team:003-create-reporting-procedures
--comment: Create stored procedures for reporting operations
CREATE PROCEDURE sp_GetReportPerformance
    @StartDate DATETIME2,
    @EndDate DATETIME2
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.report_name,
        r.report_type,
        COUNT(re.id) as total_executions,
        AVG(DATEDIFF(second, re.started_at, re.completed_at)) as avg_duration_seconds,
        SUM(CASE WHEN re.execution_status = 'SUCCESS' THEN 1 ELSE 0 END) as successful_runs,
        SUM(CASE WHEN re.execution_status = 'FAILED' THEN 1 ELSE 0 END) as failed_runs,
        AVG(CAST(re.row_count AS FLOAT)) as avg_row_count
    FROM reports r
    LEFT JOIN report_executions re ON r.id = re.report_id
    WHERE re.started_at BETWEEN @StartDate AND @EndDate
    GROUP BY r.id, r.report_name, r.report_type
    ORDER BY total_executions DESC;
END;

CREATE PROCEDURE sp_CleanupOldExecutions
    @RetentionDays INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CutoffDate DATETIME2 = DATEADD(day, -@RetentionDays, GETUTCDATE());

    DELETE FROM report_executions
    WHERE completed_at < @CutoffDate
    AND execution_status IN ('SUCCESS', 'FAILED');

    SELECT @@ROWCOUNT as DeletedRows;
END;