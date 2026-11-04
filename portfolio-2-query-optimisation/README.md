# Portfolio 2 – Query Processing and Optimisation

**Data volume:** 150,000 orders, ~300,000 order items, 20,000 customers, 5,000 products (see Portfolio 1).
**Method:** `./run_plans.sh before` → `psql < 02_indexes.sql` → `./run_plans.sh after`. Each query is run with `EXPLAIN (ANALYZE, BUFFERS)`. Full plans: `evidence/plans_before.txt`, `evidence/plans_after.txt`.

## Results (single run each, local Docker, PostgreSQL 16)
| Query | Description | Before (ms) | After (ms) | Plan change | Index used |
|---|---|---|---|---|---|
| Q1 | Order history of one customer | 13.79 | **0.24** | Seq Scan → Bitmap Index Scan (~58x) | `idx_orders_customer_date` (composite) |
| Q2 | Monthly revenue, delivered, 6 months | 25.93 | **14.27** | Seq Scan → Bitmap Heap Scan | `idx_orders_delivered_date` (partial) |
| Q3 | Top 10 products by units | 116.03 | 96.52 | none (still Parallel Seq Scan) | – |
| Q4 | Revenue by category/state (5-table join) | 175.03 | 157.63 | none | – |
| Q5 | Top-3 spenders per state (CTE + window) | 121.93 | 138.31 | none (difference is run-to-run noise) | – |
| Q6 | Avg rating per product (HAVING) | 10.64 | 9.96 | none | – |
| Q7 | Stale unpaid pending orders (anti-join) | 34.22 | 33.23 | Seq Scan → Bitmap Index Scan on orders | `idx_orders_pending_date` (partial) |
| Q8 | Low-stock products sold recently | 61.96 | **23.26** | Seq Scans → Index Scans, nested loop | `idx_products_lowstock` (partial), `idx_order_items_product` (covering) |

## Analysis
- **Selective lookups gain most.** Q1 reads 8 of 150,000 rows; the sequential scan read every page. A composite index `(customer_id, order_date DESC)` finds the rows *and* returns them already sorted, so the sort node disappears.
- **Partial indexes** (`WHERE status='DELIVERED'` / `'PENDING'` / `stock_qty < 20`) are smaller than full indexes and only cover the rows the queries use. Q8 improved ~2.7x because the planner switched from scanning two big tables to a nested loop driven by the ~200 low-stock products.
- **Indexes do not help queries that read most of a table.** Q3, Q4, Q5 and Q6 aggregate over all or most rows, so the planner correctly kept sequential scans (reading everything sequentially is cheaper than random index lookups). Their small changes are caching/noise, not index effects. Q5's apparent slowdown is within run-to-run variation; its plan did not change.
- **Index cost:** each index adds write overhead and storage on `orders`/`order_items`, which matters for a write-heavy checkout workload, so only indexes tied to a measured query were created.
- **Join strategy:** hash joins were used for large joins (Q3–Q5); nested loop with index scans was chosen only when one side was small (Q8).
- **Limitations:** single runs on a laptop, warm cache; for rigorous benchmarking, repeat several times and report the median. Further optimisation for Q3–Q5 would be a materialised view (pre-aggregated sales summary) rather than an index.
