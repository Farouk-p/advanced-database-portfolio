# Portfolio 4: NoSQL and Advanced Data Models (MongoDB)

## Goal
Use a NoSQL database for the part of Farpoint where it genuinely fits, build it from the same data as the relational database, and explain where it should not be used.

## What I chose and why
I used **MongoDB (a document database)** for the **transaction logs**. In a bank this data is:
- **append-only**: rows are added and never changed, so there is no risk from duplicated copies going out of date;
- **read in bulk**: customers open statements, auditors search history;
- **varied**: a cash withdrawal has a channel (ATM, POS, branch), a transfer has a counterparty account and a status, a reversal has a reason. One document type can carry exactly the fields it needs.

The balances and transfers themselves **stay in PostgreSQL**. They need strict all-or-nothing updates across several rows (Portfolio 3), and that is what relational databases are built for.

## What I did
1. `00_export_from_postgres.sh` exports every log row (246,776) from PostgreSQL as JSON, joined with the account number, customer name and the details that belong to each type.
2. `01_load.js` loads them into MongoDB and then builds a second collection of monthly statements.
3. `02_queries.js` runs queries and compares an indexed lookup with a full scan. Output: `evidence/mongo_queries_output.txt`.

To run it: start the containers (`docker compose up -d`), then
```bash
./00_export_from_postgres.sh
docker cp data/transactions.jsonl farpoint-mongo:/tmp/ && docker cp 01_load.js farpoint-mongo:/tmp/ && docker cp 02_queries.js farpoint-mongo:/tmp/
docker exec farpoint-mongo mongosh --quiet /tmp/01_load.js
docker exec farpoint-mongo mongosh --quiet /tmp/02_queries.js
```

## The data model

**Collection `transactions`** (246,776 documents): one document per balance change.
```json
{ "_id": 8841, "account_number": "3000011111",
  "customer": { "id": 1111, "name": "Ifeanyi Eze" },
  "type": "WITHDRAWAL", "direction": "DEBIT",
  "amount": "36500.00", "balance_after": "2752468.00", "at": "2026-08-03T23:48:44Z",
  "details": { "channel": "ATM" } }
```
- `details` changes with the type: `{channel}` for deposits and withdrawals, `{transfer_ref, transfer_status, counterparty, failure_reason}` for transfers.
- The customer name is **copied in** (embedded) so a statement needs no join.
- Amounts use MongoDB's `Decimal128`, not floating point, so kobo values stay exact.

**Collection `statements`** (112,486 documents): one document per account per month, holding all that month's entries, the closing balance and a count. This is called the *bucket pattern*. A customer opening a monthly statement reads **one document**, not dozens of small ones.

**Embed or reference?** I embedded the customer name and the entries because they are always read together and never edited. I did not embed balances, because a balance changes and would then be stored in two places.

## Results
| Query | Result |
|---|---|
| Q1 Newest 5 lines of an account | Works on the `transactions` collection |
| Q2 A whole month's statement | One document read from `statements` |
| Q3 Withdrawals by channel | POS 19,862, BRANCH 10,179, ATM 9,959 |
| Q4 Reversals by reason | 3,280 reversals, all `CREDIT_NOT_CONFIRMED` |
| Q5 Daily volume by type | Aggregation pipeline over the last 30 days |
| Q6 Top 5 senders | Highest sender: Funmilayo Okonkwo, N735,000 |

**Index effect (Q1, `explain("executionStats")`):**
| | Documents examined | Time |
|---|---|---|
| Before (no index) | 246,776 (the whole collection) | 60 ms |
| After (`{account_number: 1, at: -1}`) | 25 | 8 ms |

### Does the MongoDB copy match PostgreSQL?
Yes, exactly:
| | PostgreSQL `transaction_logs` | MongoDB `transactions` |
|---|---|---|
| Rows / documents | 246,776 | 246,776 |
| Total credits | 29,790,816,639.00 | 29,790,816,639.00 |
| Total debits | 2,911,520,000.00 | 2,911,520,000.00 |

(The four demo accounts from Portfolio 3 were left out of the export.)

## When NoSQL fits Farpoint, and when it does not
**Good fit:** transaction history and statements, audit and event search, anything read far more than it is written, and data whose shape varies by type. MongoDB can also spread a very large history across many servers (sharding, Portfolio 5).

**Poor fit:** the money itself. Moving N100,000 means changing two balances and writing log rows, all together or not at all, and checking rules like "balance cannot go negative". PostgreSQL does this with constraints and transactions. MongoDB's multi-document transactions exist but are less natural for this, and copying data into several documents makes it easy for copies to disagree.

**So the design is two databases:** PostgreSQL is the source of truth for balances and transfers, and MongoDB is a fast, flexible read copy of the history. In production the copy would be fed continuously, for example from the log table, instead of by a one-off export.

## What I learned
- A document model is not "better", it is different: it makes reads fast by storing things together, and in exchange it makes updating shared data harder.
- Choosing what to embed comes down to one question: is this data always read together, and does it ever change?
- The index test shows why indexes matter in either type of database: 246,776 documents examined became 25.
- Key-value stores, column stores and graph databases would suit other jobs (sessions and one-time codes, huge analytics tables, tracing money between linked accounts). I did not build them, since the assessment asks for one example.

## Limits
This is a one-off copy, not a live feed. I tested on one machine, and the timings are single runs.
