--liquibase formatted sql

--changeset DM-4006:006
--comment: Add products table for inventory database
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'products') AND type in (N'U')
CREATE TABLE products (
    product_id INT IDENTITY(1,1) PRIMARY KEY,
    product_name NVARCHAR(255) NOT NULL,
    sku NVARCHAR(100) UNIQUE NOT NULL,
    description NVARCHAR(MAX),
    unit_price DECIMAL(10,2) NOT NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    updated_at DATETIME2 DEFAULT GETDATE()
);

--changeset DM-4007:007
--comment: Add inventory table with FK to products
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID(N'inventory') AND type in (N'U')
CREATE TABLE inventory (
    inventory_id INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT NOT NULL,
    warehouse_location NVARCHAR(100),
    quantity_on_hand INT NOT NULL DEFAULT 0,
    quantity_reserved INT NOT NULL DEFAULT 0,
    reorder_point INT NOT NULL DEFAULT 0,
    last_updated DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_inventory_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE
);
