-- Sharding design test on the real data: if Farpoint had 4 shards, how evenly would each shard key spread the work?
-- Run against any copy of the database:
--   docker exec -i farpoint-pg psql -U farpoint -d farpoint < sharding_key_test.sql
\echo '--- Option 1: hash of the account number (4 shards)'
SELECT abs(hashtext(a.account_number)) % 4 AS shard, count(*) AS log_rows,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM transaction_logs l JOIN accounts a ON a.account_id = l.account_id
GROUP BY 1 ORDER BY 1;

\echo '--- Option 2: range on transaction date (one shard per quarter, so the newest quarter takes new writes)'
SELECT date_trunc('quarter', created_at)::date AS quarter, count(*) AS log_rows
FROM transaction_logs GROUP BY 1 ORDER BY 1;

\echo '--- Option 2 in practice: where did the last 30 days of writes land?'
SELECT date_trunc('quarter', created_at)::date AS quarter, count(*) AS rows_written_last_30_days
FROM transaction_logs WHERE created_at >= now() - interval '30 days' GROUP BY 1 ORDER BY 1;

\echo '--- A customer''s accounts under option 1 (does one customer stay on one shard if we shard by customer_id?)'
SELECT abs(hashtext(c.customer_id::text)) % 4 AS shard, count(DISTINCT a.account_id) AS accounts
FROM customers c JOIN accounts a ON a.customer_id = c.customer_id GROUP BY 1 ORDER BY 1;
