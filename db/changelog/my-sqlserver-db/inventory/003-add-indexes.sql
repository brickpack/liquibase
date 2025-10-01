--liquibase formatted sql

--changeset DM-4008:0.1.008
--comment: Create index for products SKU lookup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('products') AND name = 'idx_products_sku'
CREATE NONCLUSTERED INDEX idx_products_sku ON products(sku);

--changeset DM-4009:0.1.009
--comment: Create index for inventory product_id lookup
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('inventory') AND name = 'idx_inventory_product_id'
CREATE NONCLUSTERED INDEX idx_inventory_product_id ON inventory(product_id);

--changeset DM-4010:0.1.010
--comment: Create index for inventory warehouse location
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM sys.indexes WHERE object_id = OBJECT_ID('inventory') AND name = 'idx_inventory_warehouse'
CREATE NONCLUSTERED INDEX idx_inventory_warehouse ON inventory(warehouse_location);