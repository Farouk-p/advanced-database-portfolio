-- Demo 1: commit, rollback, and reversing a failed transfer.
-- Accounts: 6501 = Amaka (N500,000), 6502 = Tunde (N300,000), 6504 = Zainab's second account.
SELECT demo_reset(500000, 300000, 60000, 60000);
\pset footer off

\echo
\echo '=== Starting balances'
SELECT account_id, balance FROM accounts WHERE account_id IN (6501, 6502) ORDER BY 1;

\echo
\echo '=== A) COMMIT: Amaka sends N100,000 to Tunde. Both sides change together.'
BEGIN;
UPDATE accounts SET balance = balance - 100000 WHERE account_id = 6501;
UPDATE accounts SET balance = balance + 100000 WHERE account_id = 6502;
INSERT INTO transfers (reference, from_account_id, to_account_id, amount, status)
VALUES ('DEMO-A', 6501, 6502, 100000, 'COMPLETED') RETURNING transfer_id \gset
INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, transfer_id)
SELECT 6501, 'TRANSFER_OUT', 'DEBIT',  100000, balance, :transfer_id FROM accounts WHERE account_id = 6501;
INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, transfer_id)
SELECT 6502, 'TRANSFER_IN',  'CREDIT', 100000, balance, :transfer_id FROM accounts WHERE account_id = 6502;
COMMIT;
SELECT account_id, balance FROM accounts WHERE account_id IN (6501, 6502) ORDER BY 1;

\echo
\echo '=== B) ROLLBACK: Tunde tries to send N900,000 but only has N400,000.'
\echo '    The debit breaks the "balance >= 0" rule, so the whole transaction is undone.'
BEGIN;
UPDATE accounts SET balance = balance - 900000 WHERE account_id = 6502;   -- fails here
UPDATE accounts SET balance = balance + 900000 WHERE account_id = 6501;   -- never runs: transaction is aborted
ROLLBACK;
\echo 'Balances after the rollback (unchanged, and Amaka was not credited):'
SELECT account_id, balance FROM accounts WHERE account_id IN (6501, 6502) ORDER BY 1;

\echo
\echo '=== C) REVERSING A FAILED TRANSFER: the money leaves Amaka, but the receiving account is frozen.'
\echo '    Nothing is deleted. The bank writes a compensating REVERSAL entry, so the audit trail stays complete.'
UPDATE accounts SET status = 'FROZEN' WHERE account_id = 6504;
BEGIN;
UPDATE accounts SET balance = balance - 50000 WHERE account_id = 6501;                    -- step 1: debit sender
INSERT INTO transfers (reference, from_account_id, to_account_id, amount, status)
VALUES ('DEMO-C', 6501, 6504, 50000, 'PENDING') RETURNING transfer_id \gset
INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, transfer_id)
SELECT 6501, 'TRANSFER_OUT', 'DEBIT', 50000, balance, :transfer_id FROM accounts WHERE account_id = 6501;
\echo 'Step 2: try to credit the receiver. Only ACTIVE accounts can be credited. How many rows changed?'
UPDATE accounts SET balance = balance + 50000 WHERE account_id = 6504 AND status = 'ACTIVE';   -- UPDATE 0
\echo 'Zero rows. The credit failed, so give the money back to the sender:'
UPDATE accounts SET balance = balance + 50000 WHERE account_id = 6501;
INSERT INTO transaction_logs (account_id, tx_type, direction, amount, balance_after, transfer_id)
SELECT 6501, 'REVERSAL', 'CREDIT', 50000, balance, :transfer_id FROM accounts WHERE account_id = 6501;
UPDATE transfers SET status = 'REVERSED', failure_reason = 'CREDIT_NOT_CONFIRMED' WHERE transfer_id = :transfer_id;
COMMIT;
\echo 'Amaka is back to N400,000 and the transfer is marked REVERSED:'
SELECT account_id, balance FROM accounts WHERE account_id = 6501;
SELECT reference, status, failure_reason FROM transfers WHERE reference = 'DEMO-C';
\echo 'Amaka''s statement shows the full story:'
SELECT tx_type, direction, amount, balance_after FROM transaction_logs WHERE account_id = 6501 ORDER BY log_id;

\echo
\echo '=== D) The transfer_funds() function does all of this safely in one call.'
SELECT demo_reset(500000, 300000, 60000, 60000);
\echo '1) normal transfer:'
SELECT transfer_funds('FN-1', 6501, 6502, 100000);
\echo '2) more than the balance:'
SELECT transfer_funds('FN-2', 6502, 6501, 900000);
\echo '3) same request sent twice (a retry):'
SELECT transfer_funds('FN-1', 6501, 6502, 100000);
UPDATE accounts SET status = 'FROZEN' WHERE account_id = 6504;
\echo '4) receiver is frozen:'
SELECT transfer_funds('FN-4', 6501, 6504, 1000);
SELECT reference, status, failure_reason FROM transfers WHERE reference LIKE 'FN-%' ORDER BY transfer_id;
\echo 'Balances (only transfer FN-1 moved money):'
SELECT account_id, balance FROM accounts WHERE account_id IN (6501, 6502) ORDER BY 1;

\echo
\echo '=== E) AUDIT: after all of that, does every account in the bank still equal its log? (0 = yes)'
SELECT demo_reset(500000, 300000, 60000, 60000);
SELECT count(*) AS accounts_that_do_not_match
FROM accounts a
WHERE a.balance <> coalesce((SELECT sum(CASE direction WHEN 'CREDIT' THEN amount ELSE -amount END)
                             FROM transaction_logs l WHERE l.account_id = a.account_id), 0);
