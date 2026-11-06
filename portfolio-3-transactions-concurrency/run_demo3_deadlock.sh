#!/usr/bin/env bash
# Demo 3: deadlock. Amaka (6501) sends money to Tunde (6502) at the same moment Tunde sends money to Amaka.
PSQL="docker exec -i farpoint-pg psql -U kobo -d farpoint -q"
reset() { echo "SELECT demo_reset(500000, 300000, 60000, 60000);" | $PSQL > /dev/null; }
{
echo "=========== 1) Naive code: each transfer locks its own sender first, then the receiver ==========="
reset
$PSQL -v ON_ERROR_STOP=1 <<SQL 2>&1 || echo "T1 (Amaka -> Tunde): CANCELLED by PostgreSQL (deadlock victim). Its changes were rolled back." &
BEGIN;
UPDATE accounts SET balance = balance - 10000 WHERE account_id = 6501;   -- T1 locks Amaka
SELECT pg_sleep(2) \gset
UPDATE accounts SET balance = balance + 10000 WHERE account_id = 6502;   -- T1 now needs Tunde
COMMIT;
\echo T1 (Amaka -> Tunde): finished
SQL
sleep 0.5
$PSQL -v ON_ERROR_STOP=1 <<SQL 2>&1 || echo "T2 (Tunde -> Amaka): CANCELLED by PostgreSQL (deadlock victim). Its changes were rolled back." &
BEGIN;
UPDATE accounts SET balance = balance - 10000 WHERE account_id = 6502;   -- T2 locks Tunde
SELECT pg_sleep(2) \gset
UPDATE accounts SET balance = balance + 10000 WHERE account_id = 6501;   -- T2 now needs Amaka
COMMIT;
\echo T2 (Tunde -> Amaka): finished
SQL
wait
echo "One transaction was cancelled by PostgreSQL. Only the survivor's change was applied:"
echo "SELECT account_id, balance FROM accounts WHERE account_id IN (6501,6502) ORDER BY 1;" | $PSQL

echo; echo "=========== 2) transfer_funds(): always locks the lower account number first ==========="
reset
echo "SELECT 'T1 Amaka -> Tunde: ' || transfer_funds('DL-1', 6501, 6502, 10000, 2) AS result;" | $PSQL 2>&1 &
sleep 0.5
echo "SELECT 'T2 Tunde -> Amaka: ' || transfer_funds('DL-2', 6502, 6501, 10000, 2) AS result;" | $PSQL 2>&1 &
wait
echo "Both completed, no deadlock. Amaka and Tunde each sent N10,000, so the balances end where they started:"
echo "SELECT account_id, balance FROM accounts WHERE account_id IN (6501,6502) ORDER BY 1;" | $PSQL
reset
} 2>&1 | tee evidence/demo3_deadlock.txt
