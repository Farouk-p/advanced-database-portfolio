#!/usr/bin/env bash
# Demo 2: the double-spend problem.
# Amaka's account (6501) holds N100,000. Two ATMs each try to pay out N80,000 at the same moment.
# The correct result: ONE withdrawal is approved, the other refused, and N20,000 is left.
PSQL="docker exec -i farpoint-pg psql -U kobo -d farpoint -q"
reset()  { echo "SELECT demo_reset(100000, 300000, 60000, 60000);" | $PSQL > /dev/null; }
result() { echo "SELECT balance AS final_balance FROM accounts WHERE account_id = 6501;" | $PSQL; }

# Each ATM session reads the balance, "thinks" for 2 seconds, checks the money is there, then withdraws.
atm() {   # $1=name  $2=isolation level  $3=lock clause  $4=start delay
  sleep "$4"
  $PSQL -v ON_ERROR_STOP=1 <<SQL || echo "$1: CANCELLED by the database (serialization error). Nothing was paid out; the ATM must retry."
BEGIN ISOLATION LEVEL $2;
SELECT balance AS bal FROM accounts WHERE account_id = 6501 $3 \gset
\echo $1: sees a balance of :bal
SELECT pg_sleep(2) \gset
SELECT (:bal >= 80000) AS ok \gset
\if :ok
  UPDATE accounts SET balance = :bal - 80000 WHERE account_id = 6501;
  \echo $1: withdrawal of 80,000 APPROVED
\else
  \echo $1: withdrawal REFUSED, not enough money
\endif
COMMIT;
SQL
}

# The safest version: do the check and the change in ONE statement.
atm_atomic() {
  sleep "$1"
  $PSQL <<SQL
SELECT pg_sleep(2) \gset
UPDATE accounts SET balance = balance - 80000 WHERE account_id = 6501 AND balance >= 80000;
\echo $2: rows updated = :ROW_COUNT   (1 = approved, 0 = refused)
SQL
}

run() { echo; echo "=========== $1 ==========="; reset; shift
  atm ATM-A "$1" "$2" 0 2>&1 & atm ATM-B "$1" "$2" 0.5 2>&1 & wait; result; }

{
run "1) No protection (READ COMMITTED): BOTH approved = N160,000 paid out of a N100,000 account, yet the balance only dropped by N80,000" "READ COMMITTED" ""
run "2) Row lock (SELECT ... FOR UPDATE): the second ATM waits, then sees N20,000 and is refused" "READ COMMITTED" "FOR UPDATE"
run "3) Stricter isolation (REPEATABLE READ): the database stops the second ATM with an error" "REPEATABLE READ" ""
echo; echo "=========== 4) One atomic UPDATE with the check built in ==========="; reset
atm_atomic 0 ATM-A 2>&1 & atm_atomic 0.5 ATM-B 2>&1 & wait; result
reset
} 2>&1 | tee evidence/demo2_double_spend.txt
