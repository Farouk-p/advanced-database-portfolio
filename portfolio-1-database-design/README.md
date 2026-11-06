# Portfolio 1: Database Design and Modelling

## Goal
Design the relational database for a small digital bank and explain why it is built the way it is.

## The case study: Farpoint
Farpoint is a made-up Nigerian digital bank. I chose a bank because the work here (moving money safely) is exactly what advanced database topics are about.

| Question | Answer |
|---|---|
| **What does the business do?** | Holds customer accounts and lets customers deposit, withdraw and transfer money. |
| **Who uses the database?** | Customers (through a mobile app), bank staff who help customers, and auditors who check the books. |
| **What data is stored?** | Customers, accounts, deposits, withdrawals, transfers and transaction logs. |
| **Key operations** | Transfer funds, reverse a failed transaction, audit account balances. |

## What I built
Six tables, one for each kind of data above. The full SQL is in `01_schema.sql` and the diagram is in `er-diagram.md`.

| Table | What it stores |
|---|---|
| `customers` | Name, email, phone and BVN (the national bank verification number). |
| `accounts` | A 10-digit account number, owner, type (savings/current), balance and status. |
| `deposits` | Money paid in. |
| `withdrawals` | Money taken out. |
| `transfers` | Money moved between two accounts, with a status: pending, completed, failed or reversed. |
| `transaction_logs` | The audit trail. One row each time a balance changes, with the balance afterwards. |

### Keys and constraints (and why)
- **Primary keys:** every table has its own ID so each row can be pointed to without ambiguity.
- **Foreign keys:** an account must belong to a real customer, and a deposit must go into a real account. The database refuses rows that break this.
- **Unique:** email, BVN, account number and transfer reference cannot repeat. The unique transfer reference also stops one payment request being processed twice.
- **Checks:** amounts must be above zero, balances cannot go below zero (no overdrafts), a transfer cannot send money to the same account, and statuses must be one of the allowed words.
- **One source per log row:** a log row must point to exactly one deposit, withdrawal or transfer. A check constraint enforces this.
- **Money type:** amounts use `NUMERIC(15,2)`, not floating point, so kobo values are never rounded wrongly.

## Normalisation
Starting point, a flat "account statement" sheet:
`customer name, email, BVN, account number, account type, balance, [date, type, amount, balance after, other party]...`

1. **First normal form (1NF):** the statement lines repeat many times in one row. I moved each line into its own row, in `deposits`, `withdrawals`, `transfers` and `transaction_logs`.
2. **Second normal form (2NF):** things like the account type depend only on the account, not on a single transaction line. They stay in `accounts`.
3. **Third normal form (3NF):** customer details (name, email, BVN) depend on the customer, not on the account, so they live in `customers`. A customer with two accounts is stored once.
4. **Result:** every non-key column depends on its table's key and nothing else.

### Two deliberate shortcuts (denormalisation)
- `accounts.balance` could be calculated by adding up the log, but that would be slow on every balance check. So the balance is stored, and Portfolio 2 includes an audit query to prove it still matches the log.
- `transaction_logs.balance_after` stores a running balance so a statement can be read without recalculating history.

Both are copies of data that could be derived. They are safe only if every balance change happens inside a transaction, which is what Portfolio 3 is about.

## Test data
`02_seed.sql` creates made-up but realistic data so later portfolios have something to work with: 5,000 customers, 6,500 accounts, 56,500 deposits, 40,000 withdrawals, 80,000 transfers (about 90% completed, 6% failed, 4% reversed) and the matching transaction log. The data is built so that every balance matches its log, so the audit will pass.

## How to run it
```bash
docker compose up -d       # from the repository root; the schema and data load automatically
docker exec -it farpoint-pg psql -U kobo -d farpoint -c '\dt'
```

## What happened
The schema loaded without errors and the row counts are in `evidence/row_counts.txt`.

## What I learned
Designing the constraints first (no negative balance, no self-transfer, one source per log) means the database itself rejects bad data, instead of relying on every future program to remember the rules.
