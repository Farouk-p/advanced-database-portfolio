# MIT 8103 Advanced Database Systems: Continuous Assessment Portfolio

**Student:** Popoola Farouk
**Student ID:** 301930841
**Case study:** Farpoint, a made-up Nigerian digital bank (customers, accounts, deposits, withdrawals, transfers and transaction logs).
**Operations covered:** transfer funds, reverse failed transactions, audit account balances.
**Tools:** PostgreSQL 16 (relational), MongoDB 7 (document), Docker Compose.

## Where to find things

| Portfolio | Folder | What is inside |
|---|---|---|
| 1. Design and modelling | `portfolio-1-database-design/` | ER diagram, 6-table schema, keys and constraints, normalisation, test data |
| 2. Query optimisation | `portfolio-2-query-optimisation/` | 8 bank queries, indexes, execution plans before and after, analysis |
| 3. Transactions and concurrency | `portfolio-3-transactions-concurrency/` | Commit, rollback, reversal of a failed transfer, double-spend, deadlock, isolation levels |
| 4. NoSQL | `portfolio-4-nosql/` | MongoDB model of the transaction history, queries, index evidence |
| 5. Distributed and cloud | `portfolio-5-distributed-cloud/` | Replication, failover, sync vs async, sharding test, CAP, cloud discussion |
| Final documentation | `final-documentation/` | The 2-3 page Word document for the LMS |

Every folder has its own README with the same four parts: the goal, what I did, what happened, and what I learned. Raw outputs are in each `evidence/` folder.

## How the assessment requirements are met

| Requirement from the brief | Where it is covered |
|---|---|
| Case study clearly stated | `portfolio-1-database-design/README.md` |
| ER diagram, relational schema, keys, constraints, normalisation | Portfolio 1: `er-diagram.md`, `01_schema.sql`, README |
| SQL queries, results, execution plans, indexing, performance analysis | Portfolio 2: `01_queries.sql`, `02_indexes.sql`, `evidence/plans_*.txt`, README |
| Transactions showing commit, rollback, isolation, a concurrency problem and its control | Portfolio 3: demos 1 to 4 and `evidence/` |
| NoSQL model on the same case study, with implementation and suitability | Portfolio 4: `01_load.js`, `02_queries.js`, README |
| Replication, sharding, availability, consistency or deployment evidence | Portfolio 5: `run_demo.sh`, `sharding_key_test.sql`, README |
| Operation: transfer funds | Portfolio 3 (`transfer_funds()`, demo 1) |
| Operation: reverse failed transactions | Portfolio 3 (demo 1, section C) |
| Operation: audit account balances | Portfolio 2 (Q5) and Portfolio 3 (demo 1, section E): 0 accounts out of balance |
| 2-3 page summary, GitHub link, screenshots, reflection, references, AI declaration | `final-documentation/` |

## How to run it
You need Docker Desktop.
```bash
docker compose up -d      # PostgreSQL (schema and test data load automatically, about a minute) and MongoDB
docker exec -it farpoint-pg psql -U farpoint -d farpoint -c '\dt'
```
Then follow the README in each portfolio folder. Portfolio 5 has its own `docker-compose.yml`.

## AI Use Declaration
- **Tool used:** Claude (Anthropic), through Claude Code.
- **What it was used for:** drafting the SQL, JavaScript and shell scripts, the Docker configuration and the README text.
- **How I checked it:** every script was run against the real databases, and the files in the `evidence/` folders are the actual outputs. Problems found by running were fixed, for example a slow seed script, demo scripts that printed "approved" after the database had cancelled a transaction, and a misleading cold-cache timing in Portfolio 2. The analysis was written after reading the actual plans and results.
- I am responsible for the work and can explain it.
