#!/usr/bin/env bash
# Demo 2: two concurrent checkouts on the same product (read-modify-write) under different controls.
# Session A buys 3 units, session B buys 4. Starting stock = 100, correct final = 93.
PSQL="docker exec -i naijamart-pg psql -U naija -d naijamart -q"
reset(){ echo "UPDATE products SET stock_qty=100 WHERE product_id=3;" | $PSQL; }
show(){ echo "SELECT stock_qty AS final_stock (expected 93) FROM products WHERE product_id=3;" | sed 's/ (expected 93)//' | $PSQL; }

session(){  # $1=label $2=qty $3=isolation $4=lock clause $5=start delay
  sleep "$5"
  $PSQL <<SQL
BEGIN ISOLATION LEVEL $3;
SELECT stock_qty AS "$1 read" FROM products WHERE product_id=3 $4 \gset
\echo $1 read stock=:"$1 read"
SELECT pg_sleep(2);
UPDATE products SET stock_qty = :"$1 read" - $2 WHERE product_id=3;
COMMIT;
\echo $1 committed
SQL
}
# note: psql variable names with spaces are not allowed, so use simple names below
session(){
  sleep "$5"
  $PSQL <<SQL
BEGIN ISOLATION LEVEL $3;
SELECT stock_qty AS v FROM products WHERE product_id=3 $4 \gset
\echo $1: read stock=:v
SELECT pg_sleep(2) \gset
UPDATE products SET stock_qty = :v - $2 WHERE product_id=3;
COMMIT;
\echo $1: committed
SQL
}
run(){ echo; echo "=========== $1 ==========="; reset
  session A 3 "$2" "$3" 0 2>&1 & session B 4 "$2" "$3" 0.5 2>&1 & wait; show; }

{
run "1) READ COMMITTED, no locking  -> LOST UPDATE" "READ COMMITTED" ""
run "2) READ COMMITTED + SELECT ... FOR UPDATE -> correct (B waits for A)" "READ COMMITTED" "FOR UPDATE"
run "3) REPEATABLE READ -> second writer gets serialization failure (must retry)" "REPEATABLE READ" ""
} 2>&1 | tee evidence/demo2_lost_update.txt
