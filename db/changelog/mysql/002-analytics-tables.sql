--liquibase formatted sql

--changeset mysql-team:002-create-customer-analytics-table
--comment: Create customer analytics aggregation table
CREATE TABLE customer_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_email VARCHAR(320) NOT NULL,
    total_orders INT DEFAULT 0,
    total_spent DECIMAL(15,2) DEFAULT 0.00,
    avg_order_value DECIMAL(10,2) DEFAULT 0.00,
    first_order_date DATETIME NULL,
    last_order_date DATETIME NULL,
    customer_lifetime_days INT DEFAULT 0,
    preferred_category VARCHAR(100) NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_customer_email (customer_email),
    INDEX idx_total_spent (total_spent),
    INDEX idx_last_order (last_order_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--changeset mysql-team:002-create-product-analytics-table
--comment: Create product performance analytics table
CREATE TABLE product_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT NOT NULL,
    total_sold INT DEFAULT 0,
    total_revenue DECIMAL(15,2) DEFAULT 0.00,
    avg_selling_price DECIMAL(10,2) DEFAULT 0.00,
    first_sale_date DATETIME NULL,
    last_sale_date DATETIME NULL,
    return_rate DECIMAL(5,4) DEFAULT 0.0000,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    UNIQUE KEY uk_product_id (product_id),
    INDEX idx_total_revenue (total_revenue),
    INDEX idx_total_sold (total_sold)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;