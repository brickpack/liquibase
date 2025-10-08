--liquibase formatted sql

--changeset db-admin:301
--comment: Additional indexes for performance
-- Note: Some indexes are already created inline with table definitions
-- Adding additional indexes for common query patterns

--changeset db-admin:302
--comment: Create index for customer email lookups (if not exists)
-- Already created inline with customers table, but showing pattern for adding later
-- CREATE INDEX idx_customers_email ON customers(email);

--changeset db-admin:303
--comment: Create composite index for active products by name
CREATE INDEX IF NOT EXISTS idx_products_active_name
ON products(is_active, product_name);

--changeset db-admin:304
--comment: Create index for order status queries
CREATE INDEX IF NOT EXISTS idx_orders_status
ON orders(status, order_date DESC);
