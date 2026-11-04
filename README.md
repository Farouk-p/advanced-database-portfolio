# MIT 8103 Advanced Database Systems – Continuous Assessment Portfolio

**Case study:** NaijaMart – a simulated Nigerian e-commerce platform (customers, products, orders, payments, deliveries, reviews).
**Stack:** PostgreSQL 16 (relational), MongoDB 7 (document / key-value), Docker Compose.

| Portfolio | Folder | Contents |
|---|---|---|
| 1 Design & modelling | `portfolio-1-database-design/` | ER diagram, schema DDL, normalisation, seed data (150k orders) |
| 2 Query optimisation | `portfolio-2-query-optimisation/` | 8 queries, indexes, before/after EXPLAIN ANALYZE, analysis |
| 3 Transactions & concurrency | `portfolio-3-transactions-concurrency/` | commit/rollback/savepoint, lost update, isolation levels, deadlock |
| 4 NoSQL | `portfolio-4-nosql/` | MongoDB document model, aggregations, indexes, TTL carts |
| 5 Distributed & cloud | `portfolio-5-distributed-cloud/` | PG streaming replica, Mongo replica set failover, sharding/CAP discussion |

## Quick start
```bash
docker compose up -d                         # PostgreSQL (+schema+seed) and MongoDB
cd portfolio-2-query-optimisation && ./run_plans.sh before   # etc. – see each README
```
Each portfolio README explains how it was implemented and tested; raw outputs are in each `evidence/` folder.

## AI Use Declaration
- **Tool:** Claude (Anthropic) via Claude Code.
- **Used for:** drafting SQL/JS/shell scripts, Docker configuration, and README text.
- **Verification:** every script was executed against the running databases and the outputs in `evidence/` are the real results; the seed script was debugged after the first version was too slow; analysis text was checked against the actual execution plans. The author is responsible for understanding and explaining all submitted work.
