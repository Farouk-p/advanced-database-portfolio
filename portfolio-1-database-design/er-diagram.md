# Farpoint ER diagram

GitHub draws the diagram below automatically (it is written in Mermaid).

```mermaid
erDiagram
    CUSTOMERS ||--|{ ACCOUNTS : "owns"
    ACCOUNTS  ||--o{ DEPOSITS : "receives"
    ACCOUNTS  ||--o{ WITHDRAWALS : "pays out"
    ACCOUNTS  ||--o{ TRANSFERS : "sends (from)"
    ACCOUNTS  ||--o{ TRANSFERS : "receives (to)"
    ACCOUNTS  ||--o{ TRANSACTION_LOGS : "audit trail"
    DEPOSITS    |o--o| TRANSACTION_LOGS : "logged as"
    WITHDRAWALS |o--o| TRANSACTION_LOGS : "logged as"
    TRANSFERS   |o--o{ TRANSACTION_LOGS : "logged as"

    CUSTOMERS {
        bigint customer_id PK
        varchar full_name
        varchar email UK
        varchar phone
        char bvn UK
    }
    ACCOUNTS {
        bigint account_id PK
        char account_number UK
        bigint customer_id FK
        varchar account_type
        numeric balance
        varchar status
    }
    DEPOSITS {
        bigint deposit_id PK
        bigint account_id FK
        numeric amount
        varchar channel
    }
    WITHDRAWALS {
        bigint withdrawal_id PK
        bigint account_id FK
        numeric amount
        varchar channel
    }
    TRANSFERS {
        bigint transfer_id PK
        varchar reference UK
        bigint from_account_id FK
        bigint to_account_id FK
        numeric amount
        varchar status
    }
    TRANSACTION_LOGS {
        bigint log_id PK
        bigint account_id FK
        varchar tx_type
        varchar direction
        numeric amount
        numeric balance_after
        bigint deposit_id FK
        bigint withdrawal_id FK
        bigint transfer_id FK
    }
```

**How to read it:** one customer owns one or more accounts. Every deposit, withdrawal and transfer touches an account, and each balance change also leaves one row in `transaction_logs`. A transfer has two accounts (sender and receiver), which is why `accounts` links to `transfers` twice.
