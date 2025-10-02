--liquibase formatted sql

--changeset DM-8001:001
--comment: Create ecommerce_app user for MySQL
--preconditions onFail:MARK_RAN
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM mysql.user WHERE user = 'ecommerce_app'
-- Note: Password will be set separately by manage-users.sh script
CREATE USER 'ecommerce_app'@'%' IDENTIFIED BY 'TemporaryPassword123';

--changeset DM-8002:002
--comment: Grant database privileges to ecommerce_app
--runOnChange:true
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce.* TO 'ecommerce_app'@'%';

--changeset DM-8003:003
--comment: Grant additional privileges to ecommerce_app
--runOnChange:true
-- Grant CREATE and ALTER for application-managed schema changes
GRANT CREATE, ALTER, INDEX ON ecommerce.* TO 'ecommerce_app'@'%';

-- Grant EXECUTE for stored procedures
GRANT EXECUTE ON ecommerce.* TO 'ecommerce_app'@'%';

--changeset DM-8004:004
--comment: Apply privilege changes
--runOnChange:true
FLUSH PRIVILEGES;
