#!/usr/bin/env bash
# Exports every transaction log row from PostgreSQL as one JSON document per line.
# Each document carries the account number, customer name and, depending on the type of transaction,
# different extra details (channel for cash movements, counterparty for transfers).
docker exec -i farpoint-pg psql -U farpoint -d farpoint -At <<'SQL' > data/transactions.jsonl
SELECT json_build_object(
  'log_id', l.log_id,
  'account_number', a.account_number,
  'customer_id', c.customer_id,
  'customer_name', c.full_name,
  'type', l.tx_type,
  'direction', l.direction,
  'amount', l.amount::text,
  'balance_after', l.balance_after::text,
  'at', to_char(l.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'details', CASE
     WHEN l.deposit_id    IS NOT NULL THEN json_build_object('channel', d.channel)
     WHEN l.withdrawal_id IS NOT NULL THEN json_build_object('channel', w.channel)
     ELSE json_build_object('transfer_ref', t.reference, 'transfer_status', t.status,
                            'failure_reason', t.failure_reason,
                            'counterparty', CASE WHEN l.account_id = t.from_account_id THEN ta.account_number ELSE fa.account_number END)
  END)
FROM transaction_logs l
JOIN accounts a  ON a.account_id = l.account_id
JOIN customers c ON c.customer_id = a.customer_id
LEFT JOIN deposits d    ON d.deposit_id = l.deposit_id
LEFT JOIN withdrawals w ON w.withdrawal_id = l.withdrawal_id
LEFT JOIN transfers t   ON t.transfer_id = l.transfer_id
LEFT JOIN accounts fa   ON fa.account_id = t.from_account_id
LEFT JOIN accounts ta   ON ta.account_id = t.to_account_id
WHERE l.account_id <= 6500          -- leave out the 4 demo accounts used in Portfolio 3
ORDER BY l.log_id;
SQL
wc -l data/transactions.jsonl; head -c 600 data/transactions.jsonl; echo
