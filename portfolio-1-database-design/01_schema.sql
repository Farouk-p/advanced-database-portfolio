-- Farpoint: relational schema (PostgreSQL 16)
-- Portfolio 1: Database Design and Modelling
--
-- Six tables, taken straight from the case study description:
--   customers, accounts, deposits, withdrawals, transfers, transaction_logs
--
-- Money is always NUMERIC(15,2) (never FLOAT, which cannot store naira/kobo exactly).

-- Who the bank's customers are.
CREATE TABLE customers (
    customer_id  BIGSERIAL PRIMARY KEY,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(150) NOT NULL UNIQUE,
    phone        VARCHAR(20)  NOT NULL,
    bvn          CHAR(11)     NOT NULL UNIQUE CHECK (bvn ~ '^[0-9]{11}$'),  -- bank verification number
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- A customer can hold more than one account (e.g. savings and current).
CREATE TABLE accounts (
    account_id      BIGSERIAL PRIMARY KEY,
    account_number  CHAR(10)  NOT NULL UNIQUE CHECK (account_number ~ '^[0-9]{10}$'),  -- NUBAN style
    customer_id     BIGINT    NOT NULL REFERENCES customers(customer_id),
    account_type    VARCHAR(10) NOT NULL CHECK (account_type IN ('SAVINGS','CURRENT')),
    balance         NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),  -- no overdrafts
    status          VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Money paid in.
CREATE TABLE deposits (
    deposit_id  BIGSERIAL PRIMARY KEY,
    account_id  BIGINT NOT NULL REFERENCES accounts(account_id),
    amount      NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    channel     VARCHAR(10) NOT NULL CHECK (channel IN ('BRANCH','POS','MOBILE')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Money taken out.
CREATE TABLE withdrawals (
    withdrawal_id  BIGSERIAL PRIMARY KEY,
    account_id     BIGINT NOT NULL REFERENCES accounts(account_id),
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    channel        VARCHAR(10) NOT NULL CHECK (channel IN ('ATM','POS','BRANCH')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Money moved from one account to another.
-- "reference" is unique so the same payment request cannot be processed twice.
CREATE TABLE transfers (
    transfer_id      BIGSERIAL PRIMARY KEY,
    reference        VARCHAR(30) NOT NULL UNIQUE,
    from_account_id  BIGINT NOT NULL REFERENCES accounts(account_id),
    to_account_id    BIGINT NOT NULL REFERENCES accounts(account_id),
    amount           NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    status           VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                     CHECK (status IN ('PENDING','COMPLETED','FAILED','REVERSED')),
    failure_reason   VARCHAR(40),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (from_account_id <> to_account_id)      -- you cannot send money to yourself
);

-- The audit trail: one row every time an account balance changes.
-- Each row points to exactly one source (a deposit, a withdrawal or a transfer)
-- and stores the balance after the change, so any balance can be re-checked later.
CREATE TABLE transaction_logs (
    log_id         BIGSERIAL PRIMARY KEY,
    account_id     BIGINT NOT NULL REFERENCES accounts(account_id),
    tx_type        VARCHAR(12) NOT NULL
                   CHECK (tx_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER_OUT','TRANSFER_IN','REVERSAL')),
    direction      VARCHAR(6) NOT NULL CHECK (direction IN ('CREDIT','DEBIT')),
    amount         NUMERIC(15,2) NOT NULL CHECK (amount > 0),
    balance_after  NUMERIC(15,2) NOT NULL CHECK (balance_after >= 0),
    deposit_id     BIGINT REFERENCES deposits(deposit_id),
    withdrawal_id  BIGINT REFERENCES withdrawals(withdrawal_id),
    transfer_id    BIGINT REFERENCES transfers(transfer_id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (num_nonnulls(deposit_id, withdrawal_id, transfer_id) = 1)
);
