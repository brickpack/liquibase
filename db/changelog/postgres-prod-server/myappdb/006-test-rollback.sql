--liquibase formatted sql

--changeset test-rollback:001
--comment: Test table for rollback functionality
--rollback DROP TABLE IF EXISTS rollback_test CASCADE;
CREATE TABLE IF NOT EXISTS rollback_test (
    id SERIAL PRIMARY KEY,
    test_data VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

--changeset test-rollback:002
--comment: Insert test data
--rollback DELETE FROM rollback_test WHERE test_data = 'rollback test';
INSERT INTO rollback_test (test_data)
VALUES ('rollback test')
ON CONFLICT DO NOTHING;
