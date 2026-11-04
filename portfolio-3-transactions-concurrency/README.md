# Portfolio 3 – Transactions and Concurrency (PostgreSQL 16)

All demos run against the NaijaMart database. Scripts are re-runnable; output is saved in `evidence/`.

| Script | Shows | Evidence |
|---|---|---|
| `01_commit_rollback.sql` / `run_demo1.sh` | COMMIT, ROLLBACK, SAVEPOINT | `evidence/demo1_commit_rollback.txt` |
| `run_demo2.sh` | Lost update, fix with row lock, REPEATABLE READ | `evidence/demo2_lost_update.txt` |
| `run_demo3.sh` | Non-repeatable read, deadlock | `evidence/demo3_isolation_deadlock.txt` |

## 1. Atomicity (demo 1)
- **A – COMMIT:** an order insert, order_item insert and stock decrement succeed together (stock of product 1: 68 → 66).
- **B – ROLLBACK:** the stock update violates `CHECK (stock_qty >= 0)`; the transaction aborts and the already-inserted `orders` row disappears (0 rows found) and stock is unchanged. This is atomicity: all-or-nothing.
- **C – SAVEPOINT:** an invalid payment (negative amount) is rolled back to the savepoint only; the order stays and a FAILED payment is recorded as PENDING order – partial recovery inside one transaction.

## 2. Lost update (demo 2)
Two customers buy 3 and 4 units of product 3 (stock 100, correct result 93). Each session reads stock, waits 2 s (simulating application work), then writes `read_value - qty`.
| Control | Final stock | Result |
|---|---|---|
| READ COMMITTED, no lock | **96** | A's purchase is lost (both read 100) |
| READ COMMITTED + `SELECT ... FOR UPDATE` | **93** | B blocks until A commits, then reads 97 – correct |
| REPEATABLE READ | 97 | B receives `ERROR: could not serialize access due to concurrent update`; its transaction is aborted (the "B: committed" echo line is only the script's echo – the COMMIT of an aborted tx is a rollback). The application must retry. Stock stays consistent. |

**Lesson:** pessimistic locking (`FOR UPDATE`) or an atomic `UPDATE products SET stock_qty = stock_qty - n WHERE stock_qty >= n` prevents overselling; stronger isolation prevents anomalies but requires retry logic.

## 3. Non-repeatable read (demo 3)
Reader reads price twice while a writer commits in between.
- READ COMMITTED: 1000 → **2000** (non-repeatable read)
- REPEATABLE READ: 1000 → **1000** (snapshot isolation – stable view)

## 4. Deadlock
T1 updates product 4 then 5; T2 updates 5 then 4. PostgreSQL detected the cycle (`ERROR: deadlock detected`), aborted one transaction, and the other completed (final stock 99/99 – only one transaction's changes applied). **Prevention:** always acquire locks in a consistent order (e.g. sort product ids in the checkout transaction), keep transactions short, and retry on deadlock.

## Isolation summary (PostgreSQL)
READ COMMITTED (default) prevents dirty reads only; REPEATABLE READ is snapshot isolation (prevents non-repeatable and phantom reads, may fail with serialization errors); SERIALIZABLE additionally detects write-skew. PostgreSQL never allows dirty reads (READ UNCOMMITTED behaves as READ COMMITTED).
