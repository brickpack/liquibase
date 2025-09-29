--liquibase formatted sql

--changeset myapp-team:003-create-index-products-sku
--comment: Create index for products SKU lookup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('products') AND name = 'idx_products_sku'
CREATE NONCLUSTERED INDEX idx_products_sku ON products(sku);

--changeset myapp-team:003-create-index-inventory-product-id
--comment: Create index for inventory product_id lookup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('inventory') AND name = 'idx_inventory_product_id'
CREATE NONCLUSTERED INDEX idx_inventory_product_id ON inventory(product_id);

--changeset myapp-team:003-create-index-inventory-warehouse
--comment: Create index for inventory warehouse location
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('inventory') AND name = 'idx_inventory_warehouse'
CREATE NONCLUSTERED INDEX idx_inventory_warehouse ON inventory(warehouse_location);