-- Portfolio 2: eight queries a bank would really run.
-- Each one is timed with EXPLAIN (ANALYZE, BUFFERS) before and after indexing.

-- Q1: Statement for one account (what a customer sees in the app), newest first
SELECT created_at, tx_type, direction, amount, balance_after
FROM transaction_logs
WHERE account_id = 1234
ORDER BY created_at DESC
LIMIT 50;

-- Q2: Daily money movement over the last 30 days
SELECT created_at::date AS day, tx_type, count(*) AS transactions, sum(amount) AS total_naira
FROM transaction_logs
WHERE created_at >= now() - interval '30 days'
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q3: Top 10 senders by total amount transferred out
SELECT c.full_name, a.account_number, sum(t.amount) AS total_sent
FROM transfers t
JOIN accounts  a ON a.account_id  = t.from_account_id
JOIN customers c ON c.customer_id = a.customer_id
WHERE t.status = 'COMPLETED'
GROUP BY c.full_name, a.account_number
ORDER BY total_sent DESC
LIMIT 10;

-- Q4: Failed transfers in the last 90 days, grouped by reason
SELECT failure_reason, count(*) AS failed, sum(amount) AS value_naira
FROM transfers
WHERE status = 'FAILED' AND created_at >= now() - interval '90 days'
GROUP BY failure_reason
ORDER BY failed DESC;

-- Q5: AUDIT. Does every stored balance match the sum of its log entries? (should return 0 rows)
SELECT a.account_id, a.account_number, a.balance AS stored_balance, l.calculated_balance
FROM accounts a
JOIN (SELECT account_id,
             sum(CASE direction WHEN 'CREDIT' THEN amount ELSE -amount END) AS calculated_balance
      FROM transaction_logs GROUP BY account_id) l ON l.account_id = a.account_id
WHERE a.balance <> l.calculated_balance;

-- Q6: Dormant accounts: no activity at all in the last 180 days
SELECT a.account_id, a.account_number, a.balance
FROM accounts a
WHERE a.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM transaction_logs l
                  WHERE l.account_id = a.account_id AND l.created_at >= now() - interval '180 days');

-- Q7: Total money held per customer across all their accounts (top 10)
SELECT c.customer_id, c.full_name, count(*) AS accounts, sum(a.balance) AS total_balance
FROM customers c JOIN accounts a ON a.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name
ORDER BY total_balance DESC
LIMIT 10;

-- Q8: Reversed transfers with the sender's name and when the money was returned
SELECT t.reference, c.full_name, t.amount, t.created_at AS sent_at, l.created_at AS returned_at
FROM transfers t
JOIN accounts a ON a.account_id = t.from_account_id
JOIN customers c ON c.customer_id = a.customer_id
JOIN transaction_logs l ON l.transfer_id = t.transfer_id AND l.tx_type = 'REVERSAL'
WHERE t.status = 'REVERSED' AND t.created_at >= now() - interval '90 days'
ORDER BY t.created_at DESC
LIMIT 20;
