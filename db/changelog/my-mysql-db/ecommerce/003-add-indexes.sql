--liquibase formatted sql

--changeset myapp-team:003-create-index-orders-customer-id
--comment: Create index for orders customer_id
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'orders' AND index_name = 'idx_orders_customer_id'
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

--changeset myapp-team:003-create-index-orders-status
--comment: Create index for orders status
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'orders' AND index_name = 'idx_orders_status'
CREATE INDEX idx_orders_status ON orders(status);