#!/usr/bin/env bash
# Demo 3: non-repeatable read (READ COMMITTED) vs stable snapshot (REPEATABLE READ); Demo 4: deadlock
PSQL="docker exec -i naijamart-pg psql -U naija -d naijamart -q"
reset(){ echo "UPDATE products SET price=1000, stock_qty=100 WHERE product_id IN (4,5);" | $PSQL; }
reader(){ $PSQL <<SQL
BEGIN ISOLATION LEVEL $1;
SELECT price AS first_read FROM products WHERE product_id=4;
SELECT pg_sleep(2) \gset
SELECT price AS second_read FROM products WHERE product_id=4;
COMMIT;
SQL
}
writer(){ sleep 1; echo "UPDATE products SET price=2000 WHERE product_id=4; SELECT 'writer committed price=2000' AS note;" | $PSQL; }
{
for lvl in "READ COMMITTED" "REPEATABLE READ"; do
  echo; echo "=========== Non-repeatable read test: $lvl ==========="; reset
  reader "$lvl" & writer & wait
done

echo; echo "=========== Deadlock: two transactions update products 4 and 5 in opposite order ==========="; reset
$PSQL <<SQL &
BEGIN;
UPDATE products SET stock_qty = stock_qty - 1 WHERE product_id = 4;
SELECT pg_sleep(2) \gset
UPDATE products SET stock_qty = stock_qty - 1 WHERE product_id = 5;
COMMIT;
\echo T1 finished
SQL
sleep 0.5
$PSQL <<SQL &
BEGIN;
UPDATE products SET stock_qty = stock_qty - 1 WHERE product_id = 5;
SELECT pg_sleep(2) \gset
UPDATE products SET stock_qty = stock_qty - 1 WHERE product_id = 4;
COMMIT;
\echo T2 finished
SQL
wait
echo "Fix: always lock rows in a consistent order (ORDER BY product_id) -> no deadlock."
echo "SELECT product_id, stock_qty FROM products WHERE product_id IN (4,5) ORDER BY 1;" | $PSQL
} 2>&1 | tee evidence/demo3_isolation_deadlock.txt
