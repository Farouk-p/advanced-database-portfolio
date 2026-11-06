-- Portfolio 3 setup: demo accounts, a safe transfer function, and a reset helper.
-- The demo accounts are separate from the 6,500 seeded accounts, so the demos never disturb the audited data.

-- Four demo accounts (they get account_id 6501-6504, because 6,500 accounts already exist)
INSERT INTO customers (full_name, email, phone, bvn) VALUES
  ('Amaka Nwosu',  'amaka.demo@example.com',  '08031112222', '22900000001'),
  ('Tunde Bello',  'tunde.demo@example.com',  '08032223333', '22900000002'),
  ('Zainab Lawal', 'zainab.demo@example.com', '08033334444', '22900000003');
INSERT INTO accounts (account_number, customer_id, account_type, balance)
SELECT '900000000' || n, c.customer_id, 'SAVINGS', 0
FROM (VALUES (1,'amaka.demo@example.com'),(2,'tunde.demo@example.com'),
             (3,'zainab.demo@example.com'),(4,'zainab.demo@example.com')) v(n, email)
JOIN customers c ON c.email = v.email;

-- Puts the four demo accounts back to a known state: given balances, one opening deposit each, no other history.
CREATE OR REPLACE FUNCTION demo_reset(b1 numeric, b2 numeric, b3 numeric, b4 numeric) RETURNS void AS $$
BEGIN
    DELETE FROM transaction_logs WHERE account_id BETWEEN 6501 AND 6504;
    DELETE FROM transfers    WHERE from_account_id BETWEEN 6501 AND 6504 OR to_account_id BETWEEN 6501 AND 6504;
    DELETE FROM deposits     WHERE account_id BETWEEN 6501 AND 6504;
    DELETE FROM withdrawals  WHERE account_id BETWEEN 6501 AND 6504;
    UPDATE accounts SET status = 'ACTIVE' WHERE account_id BETWEEN 6501 AND 6504;
    UPDATE accounts SET balance = CASE account_id WHEN 6501 THEN b1 WHEN 6502 THEN b2 WHEN 6503 THEN b3 ELSE b4 END
     WHERE account_id BETWEEN 6501 AND 6504;
    WITH d AS (INSERT INTO deposits (account_id, amount, channel)
               SELECT account_id, balance, 'BRANCH' FROM accounts
               WHERE account_id BETWEEN 6501 AND 6504 AND balance > 0 RETURNING deposit_id, account_id, amount)
    INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, deposit_id)
    SELECT account_id, 'DEPOSIT', 'CREDIT', amount, amount, deposit_id FROM d;
END $$ LANGUAGE plpgsql;

-- transfer_funds: the safe way to move money.
--   * locks both accounts (always the lower account_id first, so two opposite transfers cannot deadlock)
--   * refuses duplicates (same reference twice)
--   * checks the accounts are active and the sender has enough money
--   * debits, credits and writes the two log rows, all or nothing
--   * if anything fails, that work is undone but the attempt is still recorded as a FAILED transfer
-- p_delay only exists so the demos can slow things down on purpose.
CREATE OR REPLACE FUNCTION transfer_funds(p_reference text, p_from bigint, p_to bigint,
                                          p_amount numeric, p_delay numeric DEFAULT 0) RETURNS text AS $$
DECLARE
    v_from accounts%ROWTYPE;
    v_to   accounts%ROWTYPE;
    v_id   bigint;
    v_old  text;
BEGIN
    IF p_from = p_to THEN RETURN 'FAILED: SAME_ACCOUNT'; END IF;

    -- Same reference twice means the app retried a request that already went through.
    SELECT status INTO v_old FROM transfers WHERE reference = p_reference;
    IF FOUND THEN RETURN 'DUPLICATE: ' || p_reference || ' was already processed (' || v_old || ')'; END IF;

    -- Lock both accounts, lowest id first.
    PERFORM 1 FROM accounts WHERE account_id = least(p_from, p_to) FOR UPDATE;
    PERFORM pg_sleep(p_delay);
    PERFORM 1 FROM accounts WHERE account_id = greatest(p_from, p_to) FOR UPDATE;
    SELECT * INTO v_from FROM accounts WHERE account_id = p_from;
    SELECT * INTO v_to   FROM accounts WHERE account_id = p_to;

    BEGIN   -- everything in this block is undone if it raises an error
        IF v_from.status <> 'ACTIVE' OR v_to.status <> 'ACTIVE' THEN RAISE EXCEPTION 'ACCOUNT_NOT_ACTIVE'; END IF;
        IF v_from.balance < p_amount THEN RAISE EXCEPTION 'INSUFFICIENT_FUNDS'; END IF;

        INSERT INTO transfers (reference, from_account_id, to_account_id, amount, status)
        VALUES (p_reference, p_from, p_to, p_amount, 'COMPLETED') RETURNING transfer_id INTO v_id;
        UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE account_id = p_to;
        INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, transfer_id)
        VALUES (p_from, 'TRANSFER_OUT', 'DEBIT',  p_amount, v_from.balance - p_amount, v_id),
               (p_to,   'TRANSFER_IN',  'CREDIT', p_amount, v_to.balance   + p_amount, v_id);
        RETURN 'COMPLETED';
    EXCEPTION WHEN OTHERS THEN
        INSERT INTO transfers (reference, from_account_id, to_account_id, amount, status, failure_reason)
        VALUES (p_reference, p_from, p_to, p_amount, 'FAILED', left(SQLERRM, 40));
        RETURN 'FAILED: ' || SQLERRM;
    END;
END $$ LANGUAGE plpgsql;
