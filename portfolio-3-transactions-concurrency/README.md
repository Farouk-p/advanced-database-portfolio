# Portfolio 3: Transactions and Concurrency

## Goal
Show that Farpoint can move money safely: that a transfer either fully happens or not at all, that failed transfers are reversed cleanly, and that two people using the same account at the same time cannot break the books.

## What I did
Everything runs against the Farpoint PostgreSQL database. I created four demo accounts (Amaka, Tunde and two for Zainab) so the 6,500 audited accounts are never touched. `01_setup.sql` also contains `transfer_funds()`, a function that does a transfer safely.

| Script | What it shows | Evidence |
|---|---|---|
| `02_demo1_commit_rollback_reversal.sql` | Commit, rollback, reversing a failed transfer, the safe function, and a final audit | `evidence/demo1_commit_rollback_reversal.txt` |
| `run_demo2_double_spend.sh` | Two ATMs paying out the same money, and 3 ways to stop it | `evidence/demo2_double_spend.txt` |
| `run_demo3_deadlock.sh` | Two opposite transfers freezing each other, and the fix | `evidence/demo3_deadlock.txt` |
| `run_demo4_isolation.sh` | What each isolation level lets through | `evidence/demo4_isolation_levels.txt` |

To run them: `docker compose up -d` from the repository root, load `01_setup.sql` (`docker exec -i farpoint-pg psql -U farpoint -d farpoint < 01_setup.sql`), then run any script.

## Demo 1: commit, rollback and reversal
- **Commit (A):** Amaka sends N100,000 to Tunde. The debit, the credit, the transfer record and both log rows all succeed together, and balances go from 500,000/300,000 to 400,000/400,000.
- **Rollback (B):** Tunde tries to send N900,000 with only N400,000. The debit breaks the "balance cannot go below zero" rule, PostgreSQL reports the error, and `ROLLBACK` undoes everything. Balances are unchanged and Amaka was never credited.
- **Reversing a failed transfer (C):** The money leaves Amaka but the receiving account is frozen, so the credit changes 0 rows (`UPDATE 0`). I did not delete anything. The same transaction credits Amaka back, writes a `REVERSAL` log row and marks the transfer `REVERSED`. Her statement shows the whole story: deposit, debit, debit, reversal credit.
- **The safe function (D):** `transfer_funds()` returned `COMPLETED` for a normal transfer, `FAILED: INSUFFICIENT_FUNDS` when the money was not there, `DUPLICATE` when the same request reference arrived twice (a retry that must not pay twice), and `FAILED: ACCOUNT_NOT_ACTIVE` for the frozen account. Failed attempts are recorded as `FAILED` transfers without moving any money.
- **Audit (E):** after all of this, the audit query found **0** accounts whose balance disagreed with their log.

## Demo 2: the double-spend (lost update)
Amaka's account holds N100,000. Two ATMs each try to pay out N80,000 at the same moment. Each reads the balance, checks there is enough, then writes. The right answer is one approval and one refusal.

| Protection used | ATM-A | ATM-B | Verdict |
|---|---|---|---|
| None (default READ COMMITTED) | approved | **approved** | **Wrong.** N160,000 paid out of N100,000. The balance shows N20,000 because both wrote "100,000 minus 80,000", so one withdrawal was lost. |
| Row lock (`SELECT ... FOR UPDATE`) | approved | refused | Correct. ATM-B waits until ATM-A finishes, then sees N20,000. |
| REPEATABLE READ | approved | cancelled by the database | Correct, but the second ATM gets an error and must retry. |
| One atomic `UPDATE ... WHERE balance >= 80000` | approved | refused (0 rows) | Correct and the simplest. The check and the change happen in one step. |

The first row is the dangerous one: the final balance looks normal even though the bank lost money. Without the log this could go unnoticed, which is why the audit query matters.

## Demo 3: deadlock
Amaka sends to Tunde while Tunde sends to Amaka. In naive code each transaction locks its own sender first and then needs the other account, so each waits for the other forever. PostgreSQL detects the cycle, cancels one transaction (T1 here), and lets the other finish. Only T2's change was applied.

**Fix:** `transfer_funds()` always locks the account with the lower account number first. Two opposite transfers now queue up instead of colliding. In the second run both completed, and because each sent N10,000 the balances ended where they started.

## Demo 4: isolation levels
- **Non-repeatable read:** an auditor reads Amaka's balance twice while a N200,000 deposit commits in between. At READ COMMITTED the readings are 500,000 then **700,000**, so the same query gives two answers in one transaction. At REPEATABLE READ both readings are 500,000 because the transaction keeps its own snapshot.
- **Write skew:** Zainab has two accounts with N60,000 each, and the bank rule is "her total must stay at or above N50,000". Two ATMs each check the total (120,000), see that taking N50,000 is fine, and withdraw from different accounts. Under REPEATABLE READ both succeed and the total drops to **N20,000**, breaking the rule, because neither saw the other's change. Under SERIALIZABLE the database cancelled one ATM and the total stayed at N70,000. A CHECK constraint cannot enforce this rule because it spans two rows.

## What I learned
- Atomicity is what makes a transfer safe: debit, credit and log are one unit.
- The default isolation level (READ COMMITTED) is **not** enough for money. A read-check-write sequence needs a row lock, an atomic `UPDATE`, or a stricter isolation level.
- Stricter isolation does not make errors disappear. It turns silent wrong answers into errors that the application must catch and retry.
- Deadlocks are prevented by design, by locking in a consistent order and keeping transactions short, not by hoping they don't happen.
- A transaction log with a running balance plus an audit query gives a way to prove the books balance.

## Limits
These demos use `pg_sleep` to force the timing of the clash. In real life these races are rare and hard to reproduce, but they do happen under load. The demos use a single database server.
