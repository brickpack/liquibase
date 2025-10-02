--liquibase formatted sql

--changeset db-admin:109
--comment: Create index on customers email for faster lookups
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_customers_email' AND object_id = OBJECT_ID('customers'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_customers_email ON customers(email);
END
GO

--changeset db-admin:110
--comment: Create index on customers last name
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_customers_last_name' AND object_id = OBJECT_ID('customers'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_customers_last_name ON customers(last_name);
END
GO

--changeset db-admin:111
--comment: Create composite index on orders for customer and status queries
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_orders_customer_status' AND object_id = OBJECT_ID('orders'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_orders_customer_status ON orders(customer_id, status);
END
GO

--changeset db-admin:112
--comment: Create index on orders date for date range queries
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_orders_date' AND object_id = OBJECT_ID('orders'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_orders_date ON orders(order_date DESC);
END
GO

--changeset db-admin:113
--comment: Create composite index on order_items for order lookups
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_order_items_order_product' AND object_id = OBJECT_ID('order_items'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_order_items_order_product ON order_items(order_id, product_id);
END
GO

--changeset db-admin:114
--comment: Create index on products for active products
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_products_active' AND object_id = OBJECT_ID('products'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_products_active ON products(is_active, product_name);
END
GO

--changeset db-admin:115
--comment: Create index on products name for search
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_products_name' AND object_id = OBJECT_ID('products'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_products_name ON products(product_name);
END
GO
