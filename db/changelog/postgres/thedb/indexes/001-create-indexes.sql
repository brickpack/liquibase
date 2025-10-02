--liquibase formatted sql

--changeset db-admin:009
--comment: Create index on customers email for faster lookups
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);

--changeset db-admin:010
--comment: Create index on customers last name
CREATE INDEX IF NOT EXISTS idx_customers_last_name ON customers(last_name);

--changeset db-admin:011
--comment: Create composite index on orders for customer and status queries
CREATE INDEX IF NOT EXISTS idx_orders_customer_status ON orders(customer_id, status);

--changeset db-admin:012
--comment: Create index on orders date for date range queries
CREATE INDEX IF NOT EXISTS idx_orders_date ON orders(order_date DESC);

--changeset db-admin:013
--comment: Create composite index on order_items for order lookups
CREATE INDEX IF NOT EXISTS idx_order_items_order_product ON order_items(order_id, product_id);

--changeset db-admin:014
--comment: Create index on products for active products
CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active, product_name);

--changeset db-admin:015
--comment: Create index on products name for search
CREATE INDEX IF NOT EXISTS idx_products_name ON products(product_name);
