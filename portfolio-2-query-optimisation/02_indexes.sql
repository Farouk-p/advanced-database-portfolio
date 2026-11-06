-- Indexes added after reading the "before" plans.
-- (PostgreSQL does not index foreign-key columns automatically, so the statement and join paths needed help.)

-- Q1, Q6: find one account's log rows already sorted by time (composite index)
CREATE INDEX idx_logs_account_time ON transaction_logs (account_id, created_at DESC);

-- Q2: range scan on time
CREATE INDEX idx_logs_time ON transaction_logs (created_at);

-- Q4: only failed transfers are searched by date, so index just those rows (partial index)
CREATE INDEX idx_transfers_failed_time ON transfers (created_at) WHERE status = 'FAILED';

-- Q8: only reversed transfers are searched by date (partial index)
CREATE INDEX idx_transfers_reversed_time ON transfers (created_at) WHERE status = 'REVERSED';

-- Q8: jump from a transfer to its log rows
CREATE INDEX idx_logs_transfer ON transaction_logs (transfer_id) WHERE transfer_id IS NOT NULL;

-- Q3: join from transfers to the sending account
CREATE INDEX idx_transfers_from ON transfers (from_account_id);

-- Q7: find a customer's accounts
CREATE INDEX idx_accounts_customer ON accounts (customer_id);

ANALYZE;
