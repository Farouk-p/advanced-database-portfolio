#!/usr/bin/env bash
# Demo 4: isolation levels. (a) an auditor reads a balance twice while a deposit lands in between.
#                           (b) two ATMs each check a "keep at least N50,000 across both accounts" rule.
PSQL="docker exec -i farpoint-pg psql -U farpoint -d farpoint -q"
reset() { echo "SELECT demo_reset(500000, 300000, 60000, 60000);" | $PSQL > /dev/null; }

auditor() { $PSQL <<SQL
BEGIN ISOLATION LEVEL $1;
SELECT balance AS "first reading" FROM accounts WHERE account_id = 6501;
SELECT pg_sleep(2) \gset
SELECT balance AS "second reading" FROM accounts WHERE account_id = 6501;
COMMIT;
SQL
}
depositor() { sleep 1; echo "UPDATE accounts SET balance = balance + 200000 WHERE account_id = 6501; SELECT 'a N200,000 deposit has just been committed' AS note;" | $PSQL; }

# Zainab has two accounts (6503, 6504) holding N60,000 each. Rule: her TOTAL must stay at or above N50,000.
atm() {   # $1=name $2=isolation $3=account to withdraw N50,000 from $4=delay
  sleep "$4"
  $PSQL -v ON_ERROR_STOP=1 <<SQL || echo "$1: CANCELLED by the database (serialization error). Nothing was paid out; the ATM must retry."
BEGIN ISOLATION LEVEL $2;
SELECT sum(balance) AS total FROM accounts WHERE account_id IN (6503, 6504) \gset
\echo $1: total across both accounts is :total
SELECT pg_sleep(2) \gset
SELECT (:total - 50000 >= 50000) AS ok \gset
\if :ok
  UPDATE accounts SET balance = balance - 50000 WHERE account_id = $3;
  \echo $1: withdrawal of 50,000 allowed (rule still holds, as far as $1 can see)
\else
  \echo $1: withdrawal REFUSED
\endif
COMMIT;
SQL
}
{
for lvl in "READ COMMITTED" "REPEATABLE READ"; do
  echo; echo "=========== (a) Non-repeatable read, isolation = $lvl ==========="; reset
  auditor "$lvl" 2>&1 & depositor 2>&1 & wait
done
for lvl in "REPEATABLE READ" "SERIALIZABLE"; do
  echo; echo "=========== (b) Two ATMs, isolation = $lvl ==========="; reset
  atm ATM-A "$lvl" 6503 0 2>&1 & atm ATM-B "$lvl" 6504 0.5 2>&1 & wait
  echo "Zainab's total across both accounts afterwards (the rule says at least 50,000):"
  echo "SELECT sum(balance) AS total_balance FROM accounts WHERE account_id IN (6503,6504);" | $PSQL
done
reset
} 2>&1 | tee evidence/demo4_isolation_levels.txt
