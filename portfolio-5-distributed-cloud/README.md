# Portfolio 5: Distributed and Cloud Database Exercise

## Goal
Show how Farpoint would stay available, keep data safe and scale up when one database server is not enough, using replication, a sharding design and a discussion of consistency and cloud deployment.

## What I did
Everything below is run with `docker compose up -d` in this folder, then `./run_demo.sh` (wait about two minutes first for the replica to copy the primary). The full output is in `evidence/demo_replication_failover.txt`.

| Topic | How it was covered |
|---|---|
| Replication | PostgreSQL primary with a streaming replica, run for real |
| Availability and failover | Replica promoted to primary; MongoDB 3-node replica set with an election |
| Consistency | Synchronous versus asynchronous commits, and Mongo majority writes, run for real |
| Sharding | Design, with a test of two shard keys on the real Farpoint data |
| Cloud | Discussion only (see the honest note at the end) |

## 1. Replication in PostgreSQL
I started two PostgreSQL servers. The replica is a copy of the primary made with `pg_basebackup`, and it keeps itself up to date by streaming the primary's change log.

What the run showed:
- The primary reported the replica as `streaming`, and the replica held the same data (5,000 customers, 246,776 log rows).
- The replica is read-only: an insert there was refused (`cannot execute INSERT in a read-only transaction`).
- A statement query ran fine on the replica. **In a real bank, customer statements and reports would go to the replica so they cannot slow down transfers on the primary.**
- A deposit made on the primary showed up on the replica within a second. The measured replay delay was about 1.4 seconds.

## 2. Consistency: asynchronous versus synchronous
By default replication is **asynchronous**: the primary confirms a commit without waiting for the replica. That is fast, but if the primary were destroyed in that gap, the last few confirmed deposits could be lost. I changed one setting (`synchronous_standby_names`) to make it **synchronous**: a commit is only confirmed once the replica also has it.

| Mode | Replica up | Replica down |
|---|---|---|
| Asynchronous | Commit returns immediately | Commit returns immediately (risk: data loss if the primary then fails) |
| Synchronous | Commit took 169 ms | The commit **hung** and was still waiting after 6 seconds |

With the replica down and synchronous mode on, writes stop. I then switched back to asynchronous and the primary accepted writes alone. When the replica came back it caught up on the 3 deposits it had missed.

One detail: the cancelled deposit (N222) had already been committed on the primary before I gave up waiting, so it still appeared on the replica later. In real life this means a client that times out does not know whether its payment went through, so the system needs a way to look it up, such as the transfer reference from Portfolio 3.

**What a bank would pick:** for money, losing a confirmed deposit is worse than being briefly slow, so synchronous replication is the safer choice for the core ledger, at the cost of latency and of stopping writes when the standby is gone (a second standby reduces that risk).

## 3. Failover
I stopped the primary and ran `pg_promote()` on the replica. It stopped being a standby (`is_standby_now = f`), accepted a new deposit, and all 5 test deposits were present. The old primary must not simply be restarted, because two servers would both accept writes ("split brain"). It would have to be rebuilt as a new replica first. In production a tool such as Patroni or a managed cloud service does the promotion and the fencing automatically.

## 4. MongoDB replica set
I ran 3 MongoDB nodes as one replica set and wrote a transaction with majority acknowledgement (2 of 3 nodes must have it).
1. **Primary stopped:** within seconds another node was elected primary on its own. The confirmed transaction was still readable and new writes worked.
2. **A second node stopped (only 1 of 3 alive):** the last node stepped down and refused to confirm a majority write (`NotWritablePrimary`). It will not accept writes it cannot protect.
3. **Nodes restarted:** both rejoined as secondaries and caught up (the documents were visible on the rejoined node).

A replica set needs a **majority** to elect a primary, which is why it uses an odd number of nodes (3).

## 5. Sharding design
Sharding splits data across several servers. The key question is what to split by. I tested two choices on the real log data as if there were 4 shards (`sharding_key_test.sql`, output in `evidence/sharding_key_test.txt`).

| Shard key | Result on the real data |
|---|---|
| **Hash of account number** | Even spread: 25.1%, 25.5%, 24.8%, 24.5% of rows per shard |
| **Date range (one shard per quarter)** | Very uneven. The last 30 days of writes, 14,107 rows, **all landed on the newest quarter's shard** (a "hot shard") |

**Recommendation:** shard transaction history by a hash of the account number (or customer id), so that
- the work is spread evenly and new writes do not pile onto one server;
- one account's statement is read from one shard (a targeted query).

Costs to be aware of:
- Reports across all accounts (like the top-senders query) must ask every shard and merge the answers.
- A transfer between accounts on different shards would need a transaction across two servers, which is slow and complex. For that reason, I would keep the core balances and transfers in one strongly consistent PostgreSQL cluster as long as possible, and shard only the high-volume history (the MongoDB part from Portfolio 4) first.

## 6. Consistency and availability in the CAP theorem
CAP says that when the network splits, a system must choose between consistency and availability.

| Component | When part of the system is cut off | Choice |
|---|---|---|
| PostgreSQL ledger with synchronous replica | Writes wait or stop rather than risk an inconsistent copy | **Consistency** over availability |
| MongoDB with majority writes | The side without a majority refuses writes | **Consistency** over availability |
| Statements read from a replica | Can show slightly old data (about 1.4 s behind in my test) | **Availability** over consistency, which is fine for viewing history |

A bank should not show a wrong balance or lose a confirmed deposit, so the money path chooses consistency. Read-only history can tolerate being a little behind.

## 7. Cloud deployment
The same design maps onto managed cloud services:
- **PostgreSQL:** AWS RDS or Aurora (Multi-AZ gives automatic failover, read replicas serve statements), Azure Database for PostgreSQL, or a free option such as Neon or Supabase for a small test.
- **MongoDB:** MongoDB Atlas, whose free tier is already a 3-node replica set.
- **Safety:** automated backups with point-in-time recovery, and a replica in another region for disaster recovery.

**Honest note:** I ran the replication and failover on my own machine with Docker. I did **not** deploy to a managed cloud service in this project, so the cloud part above is a discussion, not evidence. If I add a free-tier Atlas or Neon screenshot, it goes in `evidence/`.

## What I learned
- Replication gives two benefits that are easy to mix up: copies for **safety** and copies for **scaling reads**.
- "No data loss" and "always fast" pull in opposite directions. The synchronous test showed this directly: the safe setting stops writes when the standby is gone.
- A failover is not finished when the new server takes over. You also have to make sure the old one cannot come back and accept writes.
- The shard key decides everything. A date key looks natural but sent 100% of recent writes to one shard in my test.

## Limits
Everything ran on one laptop, so "network failure" was simulated by stopping containers. Real networks also delay and drop messages, which makes failure harder to detect. Timings are single runs.
