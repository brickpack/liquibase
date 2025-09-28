--liquibase formatted sql

--changeset mysql-team:003-add-performance-indexes
--comment: Add performance indexes for e-commerce analytics
CREATE INDEX idx_products_name_fulltext ON products(name) USING FULLTEXT;
CREATE INDEX idx_products_sku_price ON products(sku, price);
CREATE INDEX idx_orders_customer_status ON orders(customer_email, status);
CREATE INDEX idx_orders_date_range ON orders(order_date, status);
CREATE INDEX idx_order_items_product_quantity ON order_items(product_id, quantity);

--changeset mysql-team:003-add-analytics-indexes
--comment: Add indexes for analytics tables
CREATE INDEX idx_customer_analytics_ltv ON customer_analytics(total_spent DESC, customer_lifetime_days DESC);
CREATE INDEX idx_customer_analytics_recency ON customer_analytics(last_order_date DESC);
CREATE INDEX idx_product_analytics_performance ON product_analytics(total_revenue DESC, total_sold DESC);

--changeset mysql-team:003-create-analytics-views
--comment: Create views for common analytics queries
CREATE VIEW v_top_customers AS
SELECT
    customer_email,
    total_orders,
    total_spent,
    avg_order_value,
    DATEDIFF(CURDATE(), last_order_date) as days_since_last_order
FROM customer_analytics
WHERE total_spent > 0
ORDER BY total_spent DESC
LIMIT 100;

CREATE VIEW v_monthly_sales AS
SELECT
    DATE_FORMAT(order_date, '%Y-%m') as month,
    COUNT(*) as total_orders,
    SUM(total_amount) as total_revenue,
    AVG(total_amount) as avg_order_value,
    COUNT(DISTINCT customer_email) as unique_customers
FROM orders
WHERE status IN ('shipped', 'delivered')
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY month DESC;