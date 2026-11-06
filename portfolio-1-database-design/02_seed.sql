-- Test data for Farpoint. It is made-up but realistic (Nigerian names, naira amounts).
-- The data is built so that every account balance equals the sum of its log entries,
-- which lets the audit query in Portfolio 2 prove the books balance.
SELECT setseed(0.42);

-- 1. Customers (5,000)
INSERT INTO customers (full_name, email, phone, bvn, created_at)
SELECT f || ' ' || l,
       lower(f || '.' || l || g || '@example.com'),
       '0' || (ARRAY['803','805','810','813','703','706','809','901'])[1 + (random()*7)::int]
           || lpad((random()*9999999)::int::text, 7, '0'),
       '22' || lpad(g::text, 9, '0'),
       now() - ((300 + random()*700) || ' days')::interval
FROM generate_series(1, 5000) g,
     LATERAL (SELECT (ARRAY['Chinedu','Adebayo','Ngozi','Fatima','Emeka','Aisha','Oluwaseun','Ibrahim','Chiamaka','Tunde',
                            'Zainab','Obinna','Funmilayo','Yusuf','Blessing','Segun','Amina','Ifeanyi','Kemi','Musa'])[1 + (g*7 % 20)] AS f,
                     (ARRAY['Okafor','Adeyemi','Balogun','Eze','Abubakar','Ogunleye','Nwosu','Bello','Okonkwo','Adewale',
                            'Lawal','Chukwu','Danjuma','Okeke','Salami','Umar','Afolabi','Nnamdi','Ojo','Garba'])[1 + (g*13 % 20)] AS l) n;

-- 2. Accounts: everyone gets a savings account, 30% also get a current account (about 6,500)
INSERT INTO accounts (account_number, customer_id, account_type, status, opened_at)
SELECT (3000000000 + c.customer_id * 10 + t.n)::text, c.customer_id,
       CASE t.n WHEN 1 THEN 'SAVINGS' ELSE 'CURRENT' END,
       CASE WHEN random() < 0.01 THEN 'FROZEN' ELSE 'ACTIVE' END,
       c.created_at + (random()*20 || ' days')::interval
FROM customers c
JOIN LATERAL (SELECT n FROM generate_series(1,2) n WHERE n = 1 OR c.customer_id % 10 < 3) t ON TRUE;

-- 3. Deposits: one opening deposit per account, plus 50,000 later ones
INSERT INTO deposits (account_id, amount, channel, created_at)
SELECT account_id, 2000000 + round(random()*3000000), 'BRANCH', opened_at FROM accounts;

INSERT INTO deposits (account_id, amount, channel, created_at)
SELECT a.account_id, 5000 + round(random()*195000),
       (ARRAY['BRANCH','POS','MOBILE'])[1 + (random()*2)::int],
       a.opened_at + interval '1 hour' + random() * (now() - a.opened_at - interval '1 hour')
FROM (SELECT 1 + floor(random()*(SELECT count(*) FROM accounts))::int AS id FROM generate_series(1,50000)) r
JOIN accounts a ON a.account_id = r.id;

-- 4. Withdrawals (40,000), always small compared with the opening deposit
INSERT INTO withdrawals (account_id, amount, channel, created_at)
SELECT a.account_id, 500 * (1 + (random()*99)::int),
       (ARRAY['ATM','POS','BRANCH'])[1 + (random()*2)::int],
       a.opened_at + interval '1 hour' + random() * (now() - a.opened_at - interval '1 hour')
FROM (SELECT 1 + floor(random()*(SELECT count(*) FROM accounts))::int AS id FROM generate_series(1,40000)) r
JOIN accounts a ON a.account_id = r.id;

-- 5. Transfers (80,000): about 90% completed, 6% failed, 4% reversed
INSERT INTO transfers (reference, from_account_id, to_account_id, amount, status, failure_reason, created_at)
SELECT 'TRF' || lpad(row_number() OVER ()::text, 9, '0'),
       t.f, t.t, t.amt,
       t.st,
       CASE t.st WHEN 'FAILED'   THEN (ARRAY['INSUFFICIENT_FUNDS','ACCOUNT_FROZEN','NETWORK_TIMEOUT'])[1 + (random()*2)::int]
                 WHEN 'REVERSED' THEN 'CREDIT_NOT_CONFIRMED' END,
       greatest(af.opened_at, at.opened_at) + interval '1 hour'
         + random() * (now() - greatest(af.opened_at, at.opened_at) - interval '1 hour')
FROM (
    SELECT f, 1 + ((f - 1 + 1 + floor(random()*(n - 1))::int) % n) AS t,   -- a different account from f
           500 * (1 + (random()*99)::int) AS amt,
           CASE WHEN r < 0.90 THEN 'COMPLETED' WHEN r < 0.96 THEN 'FAILED' ELSE 'REVERSED' END AS st
    FROM (SELECT 1 + floor(random()*(SELECT count(*) FROM accounts))::int AS f, random() AS r,
                 (SELECT count(*) FROM accounts)::int AS n
          FROM generate_series(1,80000)) x
) t
JOIN accounts af ON af.account_id = t.f
JOIN accounts at ON at.account_id = t.t;

-- 6. Transaction log: one row per balance change, with the running balance after it.
INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after,
                              deposit_id, withdrawal_id, transfer_id, created_at)
SELECT account_id, tx_type, direction, amount,
       sum(CASE direction WHEN 'CREDIT' THEN amount ELSE -amount END)
           OVER (PARTITION BY account_id ORDER BY created_at, ord),
       deposit_id, withdrawal_id, transfer_id, created_at
FROM (
    SELECT account_id, 'DEPOSIT' tx_type, 'CREDIT' direction, amount, deposit_id, NULL::bigint withdrawal_id, NULL::bigint transfer_id, created_at, 1 ord FROM deposits
    UNION ALL
    SELECT account_id, 'WITHDRAWAL', 'DEBIT', amount, NULL, withdrawal_id, NULL, created_at, 2 FROM withdrawals
    UNION ALL  -- completed transfer: money leaves the sender and arrives at the receiver
    SELECT from_account_id, 'TRANSFER_OUT', 'DEBIT',  amount, NULL, NULL, transfer_id, created_at, 3 FROM transfers WHERE status IN ('COMPLETED','REVERSED')
    UNION ALL
    SELECT to_account_id,   'TRANSFER_IN',  'CREDIT', amount, NULL, NULL, transfer_id, created_at, 4 FROM transfers WHERE status = 'COMPLETED'
    UNION ALL  -- reversed transfer: the sender gets the money back a little later
    SELECT from_account_id, 'REVERSAL',     'CREDIT', amount, NULL, NULL, transfer_id, created_at + interval '5 minutes', 5 FROM transfers WHERE status = 'REVERSED'
) ev
ORDER BY created_at, account_id;

-- 7. Set each account balance from the log (its latest balance_after)
UPDATE accounts a SET balance = l.bal
FROM (SELECT DISTINCT ON (account_id) account_id, balance_after AS bal
      FROM transaction_logs ORDER BY account_id, created_at DESC, log_id DESC) l
WHERE l.account_id = a.account_id;

ANALYZE;
