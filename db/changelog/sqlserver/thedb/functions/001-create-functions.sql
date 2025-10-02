--liquibase formatted sql

--changeset db-admin:116
--comment: Create function to calculate order total
IF OBJECT_ID('dbo.fn_calculate_order_total', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_calculate_order_total;
GO

CREATE FUNCTION dbo.fn_calculate_order_total(@order_id BIGINT)
RETURNS DECIMAL(12, 2)
AS
BEGIN
    DECLARE @total DECIMAL(12, 2);

    SELECT @total = COALESCE(SUM(quantity * unit_price), 0.00)
    FROM order_items
    WHERE order_id = @order_id;

    RETURN @total;
END
GO

--changeset db-admin:117
--comment: Create function to check product stock availability
IF OBJECT_ID('dbo.fn_check_stock_available', 'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_check_stock_available;
GO

CREATE FUNCTION dbo.fn_check_stock_available(@product_id BIGINT, @quantity INT)
RETURNS BIT
AS
BEGIN
    DECLARE @stock INT;
    DECLARE @available BIT = 0;

    SELECT @stock = stock_quantity
    FROM products
    WHERE product_id = @product_id AND is_active = 1;

    IF @stock IS NOT NULL AND @stock >= @quantity
        SET @available = 1;

    RETURN @available;
END
GO

--changeset db-admin:118
--comment: Create trigger for customers updated_at
IF OBJECT_ID('dbo.tr_customers_updated_at', 'TR') IS NOT NULL
    DROP TRIGGER dbo.tr_customers_updated_at;
GO

CREATE TRIGGER dbo.tr_customers_updated_at
ON customers
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE c
    SET updated_at = GETDATE()
    FROM customers c
    INNER JOIN inserted i ON c.customer_id = i.customer_id;
END
GO

--changeset db-admin:119
--comment: Create trigger for orders updated_at
IF OBJECT_ID('dbo.tr_orders_updated_at', 'TR') IS NOT NULL
    DROP TRIGGER dbo.tr_orders_updated_at;
GO

CREATE TRIGGER dbo.tr_orders_updated_at
ON orders
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE o
    SET updated_at = GETDATE()
    FROM orders o
    INNER JOIN inserted i ON o.order_id = i.order_id;
END
GO

--changeset db-admin:120
--comment: Create trigger for products updated_at
IF OBJECT_ID('dbo.tr_products_updated_at', 'TR') IS NOT NULL
    DROP TRIGGER dbo.tr_products_updated_at;
GO

CREATE TRIGGER dbo.tr_products_updated_at
ON products
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET updated_at = GETDATE()
    FROM products p
    INNER JOIN inserted i ON p.product_id = i.product_id;
END
GO
