--liquibase formatted sql

--changeset myapp-team:003-create-indexes
--comment: Create indexes for myappdb performance
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);