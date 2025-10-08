--liquibase formatted sql

--changeset db-admin:401 splitStatements:false
--comment: Create function to calculate order total
DELIMITER //
CREATE FUNCTION IF NOT EXISTS calculate_order_total(p_order_id BIGINT)
RETURNS DECIMAL(12, 2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12, 2);

    SELECT COALESCE(SUM(quantity * unit_price), 0.00)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;

    RETURN v_total;
END//
DELIMITER ;

--changeset db-admin:402 splitStatements:false
--comment: Create function to check product stock availability
DELIMITER //
CREATE FUNCTION IF NOT EXISTS check_stock_available(
    p_product_id BIGINT,
    p_quantity INT
)
RETURNS BOOLEAN
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_stock INT;
    DECLARE v_is_active BOOLEAN;

    SELECT stock_quantity, is_active
    INTO v_stock, v_is_active
    FROM products
    WHERE product_id = p_product_id;

    IF v_is_active AND v_stock >= p_quantity THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END//
DELIMITER ;

--changeset db-admin:403 splitStatements:false
--comment: Create procedure to update product stock
DELIMITER //
CREATE PROCEDURE IF NOT EXISTS update_product_stock(
    IN p_product_id BIGINT,
    IN p_quantity_change INT
)
BEGIN
    UPDATE products
    SET stock_quantity = stock_quantity + p_quantity_change,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = p_product_id;
END//
DELIMITER ;

--changeset db-admin:404 splitStatements:false
--comment: Create trigger to update order total on order_items insert
DELIMITER //
CREATE TRIGGER IF NOT EXISTS trg_order_items_after_insert
AFTER INSERT ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = calculate_order_total(NEW.order_id),
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = NEW.order_id;
END//
DELIMITER ;

--changeset db-admin:405 splitStatements:false
--comment: Create trigger to update order total on order_items update
DELIMITER //
CREATE TRIGGER IF NOT EXISTS trg_order_items_after_update
AFTER UPDATE ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = calculate_order_total(NEW.order_id),
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = NEW.order_id;
END//
DELIMITER ;

--changeset db-admin:406 splitStatements:false
--comment: Create trigger to update order total on order_items delete
DELIMITER //
CREATE TRIGGER IF NOT EXISTS trg_order_items_after_delete
AFTER DELETE ON order_items
FOR EACH ROW
BEGIN
    UPDATE orders
    SET total_amount = calculate_order_total(OLD.order_id),
        updated_at = CURRENT_TIMESTAMP
    WHERE order_id = OLD.order_id;
END//
DELIMITER ;
