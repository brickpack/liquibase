--liquibase formatted sql

--changeset db-admin:016 splitStatements:false
--comment: Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

--changeset db-admin:017 splitStatements:false
--comment: Create function to calculate order total
CREATE OR REPLACE FUNCTION calculate_order_total(p_order_id BIGINT)
RETURNS DECIMAL(12, 2) AS $$
DECLARE
    v_total DECIMAL(12, 2);
BEGIN
    SELECT COALESCE(SUM(quantity * unit_price), 0.00)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    RETURN v_total;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

--changeset db-admin:018 splitStatements:false
--comment: Create function to check product stock availability
CREATE OR REPLACE FUNCTION check_stock_available(p_product_id BIGINT, p_quantity INT)
RETURNS BOOLEAN AS $$
DECLARE
    v_stock INT;
BEGIN
    SELECT stock_quantity
    INTO v_stock
    FROM products
    WHERE product_id = p_product_id AND is_active = true;

    IF v_stock IS NULL THEN
        RETURN false;
    END IF;

    RETURN v_stock >= p_quantity;
END;
$$ LANGUAGE plpgsql STABLE;

--changeset db-admin:019
--comment: Create trigger for customers updated_at
DROP TRIGGER IF EXISTS trigger_customers_updated_at ON customers;
CREATE TRIGGER trigger_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

--changeset db-admin:020
--comment: Create trigger for orders updated_at
DROP TRIGGER IF EXISTS trigger_orders_updated_at ON orders;
CREATE TRIGGER trigger_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

--changeset db-admin:021
--comment: Create trigger for products updated_at
DROP TRIGGER IF EXISTS trigger_products_updated_at ON products;
CREATE TRIGGER trigger_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
