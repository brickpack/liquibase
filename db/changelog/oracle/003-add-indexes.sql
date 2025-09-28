--liquibase formatted sql

--changeset oracle-team:003-add-performance-indexes
--comment: Add performance indexes for legacy system integration
CREATE INDEX idx_legacy_customers_code ON legacy_customers(customer_code);
CREATE INDEX idx_legacy_customers_status ON legacy_customers(status, created_date);
CREATE INDEX idx_legacy_transactions_customer ON legacy_transactions(customer_id, transaction_date);
CREATE INDEX idx_legacy_transactions_type_status ON legacy_transactions(transaction_type, status);
CREATE INDEX idx_integration_log_system_status ON integration_log(system_name, status, started_at);
CREATE INDEX idx_legacy_mappings_lookup ON legacy_mappings(legacy_system, legacy_table, legacy_id);

--changeset oracle-team:003-add-partitioning
--comment: Add partitioning for large tables
-- Partition integration_log by month
ALTER TABLE integration_log MODIFY
PARTITION BY RANGE (started_at)
INTERVAL (NUMTOYMINTERVAL(1,'MONTH'))
(PARTITION p_integration_log_initial VALUES LESS THAN (DATE '2024-01-01'));

-- Partition legacy_transactions by year
ALTER TABLE legacy_transactions MODIFY
PARTITION BY RANGE (transaction_date)
INTERVAL (NUMTOYMINTERVAL(1,'YEAR'))
(PARTITION p_transactions_initial VALUES LESS THAN (DATE '2024-01-01'));

--changeset oracle-team:003-create-package-body
--comment: Create package body with implementation
CREATE OR REPLACE PACKAGE BODY PKG_LEGACY_INTEGRATION AS

    PROCEDURE sync_customer_data(p_customer_id IN NUMBER) IS
        v_log_id NUMBER;
    BEGIN
        -- Log the start of sync operation
        log_integration_event('LEGACY_CRM', 'SYNC', 'CUSTOMER', TO_CHAR(p_customer_id), 'PENDING');

        -- Sync logic would go here
        -- For now, just mark as success
        UPDATE integration_log
        SET status = 'SUCCESS', completed_at = SYSTIMESTAMP
        WHERE entity_id = TO_CHAR(p_customer_id)
        AND operation_type = 'SYNC'
        AND status = 'PENDING'
        AND ROWNUM = 1;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            log_integration_event('LEGACY_CRM', 'SYNC', 'CUSTOMER', TO_CHAR(p_customer_id), 'FAILED', SQLERRM);
            ROLLBACK;
            RAISE;
    END sync_customer_data;

    PROCEDURE log_integration_event(
        p_system_name IN VARCHAR2,
        p_operation_type IN VARCHAR2,
        p_entity_type IN VARCHAR2,
        p_entity_id IN VARCHAR2,
        p_status IN VARCHAR2,
        p_error_message IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO integration_log (
            system_name, operation_type, entity_type, entity_id, status, error_message
        ) VALUES (
            p_system_name, p_operation_type, p_entity_type, p_entity_id, p_status, p_error_message
        );
        COMMIT;
    END log_integration_event;

    FUNCTION get_new_id_from_legacy(
        p_legacy_system IN VARCHAR2,
        p_legacy_table IN VARCHAR2,
        p_legacy_id IN VARCHAR2,
        p_new_system IN VARCHAR2,
        p_new_table IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_new_id VARCHAR2(100);
    BEGIN
        SELECT new_id
        INTO v_new_id
        FROM legacy_mappings
        WHERE legacy_system = p_legacy_system
        AND legacy_table = p_legacy_table
        AND legacy_id = p_legacy_id
        AND new_system = p_new_system
        AND new_table = p_new_table
        AND is_active = 1;

        RETURN v_new_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN NULL;
        WHEN TOO_MANY_ROWS THEN
            -- Return the most recent mapping
            SELECT new_id
            INTO v_new_id
            FROM (
                SELECT new_id
                FROM legacy_mappings
                WHERE legacy_system = p_legacy_system
                AND legacy_table = p_legacy_table
                AND legacy_id = p_legacy_id
                AND new_system = p_new_system
                AND new_table = p_new_table
                AND is_active = 1
                ORDER BY updated_date DESC
            )
            WHERE ROWNUM = 1;
            RETURN v_new_id;
    END get_new_id_from_legacy;

END PKG_LEGACY_INTEGRATION;