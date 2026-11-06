# Portfolio 2: Query Processing and Optimisation

## Goal
Write the queries a bank really needs, look at how PostgreSQL runs them, and use indexes where they help.

## What I did
1. Wrote 8 queries (`01_queries.sql`), including the audit query that checks every balance against the transaction log.
2. Ran each one under `EXPLAIN (ANALYZE, BUFFERS)` to see the real plan and time (`./run_plans.sh before`).
3. Added 7 indexes (`02_indexes.sql`), based on what the plans showed.
4. Ran the same queries again (`./run_plans.sh after`).

Full plans are in `evidence/plans_before.txt` and `evidence/plans_after.txt`. The database has 80,000 transfers and about 247,000 log rows.

## The queries and results

| # | What the bank is asking | Before | After | What changed in the plan |
|---|---|---|---|---|
| Q1 | Statement for one account (newest 50 lines) | 16.4 ms | **0.9 ms** | Scanned the whole log table, now uses the account index |
| Q2 | Money moved per day, last 30 days | 20.3 ms | **11.2 ms** | Whole-table scan became an index range scan on time |
| Q3 | Top 10 senders by amount | 152 ms | 190 ms | Nothing. Same plan (see below) |
| Q4 | Failed transfers by reason, last 90 days | 7.7 ms | **3.2 ms** | Whole-table scan became a scan of the small "failed only" index |
| Q5 | **Audit:** stored balance vs sum of log | 58 ms | 94 ms | Nothing. Same plan (see below) |
| Q6 | Dormant accounts (no activity in 180 days) | 45 ms | **24 ms** | Scan of the log became an index-only lookup per account |
| Q7 | Total balance per customer, top 10 | 10.6 ms | 7.8 ms | Nothing. Same plan |
| Q8 | Reversed transfers and when money came back | 45 ms | **1.0 ms** | Starts from the small "reversed" index, then follows indexes (about 45x faster) |

Timings are from one run each on my laptop, with the data already in memory.

### The audit result
Q5 returned **0 rows**. That means every one of the 6,500 account balances matches its transaction log exactly, so the books balance.

## Why some queries improved and some did not
- **Looking up a few rows in a big table benefits most.** Q1 needs about 47 rows out of 247,000. Without an index PostgreSQL had to read every row. A composite index on `(account_id, created_at DESC)` goes straight to the account's rows already in time order.
- **Partial indexes are small and targeted.** Only about 6% of transfers are failed and 4% reversed, so indexes covering just those rows are tiny. Q4 and Q8 improved because of them.
- **Indexes do not help when most of the table is needed.** Q3 and Q5 add up almost every transfer or log row, so reading the whole table in order is the cheapest way. PostgreSQL correctly kept its plan. Their "after" timings are slightly worse only because of normal run-to-run variation, since the plans are identical. For a check like Q5, the real fix would be a nightly pre-calculated summary, not an index.
- **Q7 is also unchanged:** it joins two small tables, so no index was worth using.

## Lessons and limits
- **Cache matters.** The very first "before" run (right after loading the data) took 775 ms for Q1 and 790 ms for Q3 because nothing was in memory yet. Warm, they took 16 ms and 152 ms. I threw that run away and compared warm runs only, otherwise the indexes would have got credit for the cache. The script `03_drop_indexes.sql` lets the test be repeated cleanly.
- **Indexes are not free.** Every index makes inserts and updates a little slower, and a bank writes constantly. I only kept indexes that match a query I measured.
- **Foreign keys are not indexed by default in PostgreSQL.** That is why joins like Q3 and Q7 need me to add indexes myself when they matter.
- **Limits:** a single run per query on one laptop. For a rigorous benchmark I would repeat each query several times and report the median.
