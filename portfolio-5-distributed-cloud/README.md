# Portfolio 5 – Distributed and Cloud Database Exercise

Run: `docker compose up -d` (this folder), then `./run_demo.sh`. Evidence: `evidence/demo_replication_failover.txt`.

## 1. Replication – PostgreSQL streaming replication (implemented)
- `nm-pg-primary` (port 5442) and `nm-pg-replica` (5443). The replica is cloned with `pg_basebackup -R` and streams WAL from the primary (`wal_level=replica`, a `replicator` role, `hot_standby=on`).
- **Evidence:** `pg_stat_replication` shows `state = streaming, sync_state = async`; a customer inserted on the primary appeared on the replica within ~2 s; an INSERT on the replica failed with `cannot execute INSERT in a read-only transaction`; `pg_is_in_recovery() = true`.
- **Use for NaijaMart:** send catalogue browsing, search and reporting queries to the replica (read scaling) and keep checkout writes on the primary.
- **Trade-off:** replication is *asynchronous*: the replica can lag (measured replay delay ≈ 2.4 s here), so a customer could briefly not see an order just placed if reads go to the replica. Mitigation: read-your-own-writes (route a customer's reads to the primary right after checkout). `synchronous_commit` with a synchronous standby gives zero data loss at the cost of write latency.

## 2. Availability and failover – MongoDB replica set (implemented)
- 3-node set `rs0` (`mongo1..3`). The primary (mongo2) was stopped; within seconds the remaining members **elected mongo1 as new primary**, the data written before the failure (`w: majority`) was still readable, and new writes succeeded. When mongo2 restarted it rejoined as SECONDARY and caught up (count = 2 documents).
- A majority (2 of 3) must be alive to elect a primary – this is why replica sets use an odd number of nodes. With only 1 of 3 left, writes stop (consistency over availability).

## 3. Sharding strategy (design discussion for scale-out)
Sharding splits one logical dataset across nodes. For NaijaMart at national scale:
| Collection | Shard key | Reason / risk |
|---|---|---|
| `orders` | **hashed `customer_id`** | Even write distribution; a customer's order history hits one shard (targeted query). Range key on `order_date` would send all new orders to one "hot" shard. |
| `products` | `category` + `_id` (compound) or hashed `_id` | Spreads catalogue reads; category queries stay targeted. |
| `carts` | hashed `_id` | Pure key lookup. |
For PostgreSQL, equivalent options are native declarative partitioning (e.g. `orders` by month for pruning and archiving) or Citus for distribution. Cross-shard operations (global top-sellers, joins) are scatter-gather and slower, and cross-shard transactions are costly, so the checkout transaction must stay inside one shard (shard key = `customer_id`; stock handled in a separate inventory service/shard).

## 4. CAP theorem / consistency model per component
| Component | Behaviour under network partition | Choice |
|---|---|---|
| PostgreSQL primary (orders, payments, stock) | Single writer, ACID; replica may be stale | **CP** for writes; eventual consistency on replica reads |
| MongoDB replica set | Minority side cannot elect a primary → stops accepting writes | **CP** (with `w: majority`); tunable read preference |
| Product catalogue cache / reads from secondaries | Serves possibly stale data | **AP**-style, acceptable for browsing |
Money and stock require consistency (never oversell/double charge); catalogue browsing tolerates staleness. PACELC: even without partitions there is a latency vs consistency trade-off (sync vs async replication).

## 5. Cloud deployment mapping
| Need | Managed cloud option |
|---|---|
| PostgreSQL + replicas + automatic failover | AWS RDS/Aurora PostgreSQL Multi-AZ with read replicas, Azure Database for PostgreSQL, or Neon/Supabase (free tier) |
| MongoDB replica set / sharded cluster | MongoDB Atlas (M0 free tier is a 3-node replica set) |
| Cart/session cache | Redis (ElastiCache/Upstash) |
| Backups / DR | Automated snapshots + point-in-time recovery, cross-region replica |
**Status:** the replication and failover above were run locally with Docker. A managed-cloud deployment (e.g. an Atlas M0 cluster or Neon project) was **not** performed in this repository; screenshots of one can be added under `evidence/` if done.
