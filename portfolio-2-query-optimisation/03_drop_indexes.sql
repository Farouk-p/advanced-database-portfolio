-- Removes the indexes from 02_indexes.sql so the "before" test can be repeated on a warm cache.
DROP INDEX IF EXISTS idx_logs_account_time, idx_logs_time, idx_transfers_failed_time,
                     idx_transfers_reversed_time, idx_logs_transfer, idx_transfers_from, idx_accounts_customer;
ANALYZE;
