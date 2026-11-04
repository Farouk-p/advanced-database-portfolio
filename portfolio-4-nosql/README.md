# Portfolio 4 – NoSQL and Advanced Data Models (MongoDB 7, document store)

Same case study (NaijaMart). Run: `docker compose up -d mongo`, then
`docker cp 01_seed.js naijamart-mongo:/tmp/s.js && docker exec naijamart-mongo mongosh --quiet /tmp/s.js` and likewise `02_queries.js`.
Output: `evidence/mongo_queries_output.txt` (3,000 products, 5,000 customers, 30,000 orders).

## Data model (relational → document)
| Collection | Design | Why |
|---|---|---|
| `products` | Category-specific `attributes` sub-document; `reviews` **embedded** (bounded to a handful) | Phones have RAM/storage, clothes have size/colour, groceries have expiry. In SQL this needs sparse columns or an EAV table; in MongoDB each document carries its own attributes. Product page = 1 read. |
| `orders` | Line items, payment and delivery **embedded**; item name/price copied as a snapshot | An order is read and written as one unit, so one document gives a single atomic write and no joins (replaces 4 joined tables). The snapshot also preserves historical price. |
| `customers` | Addresses embedded | Few per customer, always read with the customer. |
| `carts` | Key-value style (`_id: "cart:<id>"`) with a **TTL index** | Fast lookup by key; abandoned carts expire automatically (the role Redis typically plays). |

**Embed vs reference:** embed when data is read together and bounded in size (items, reviews ≤ 5, addresses). Reference when unbounded or shared (orders reference `customer_id` and `product_id` rather than embedding the whole customer/product, so a product price change doesn't require rewriting orders).

## Implementation evidence (`02_queries.js`)
Q1 attribute search across variable fields · Q2 single-read product page · Q3 order history without joins · Q4/Q5/Q6 aggregation pipelines (`$match`, `$unwind`, `$group`, `$sort`) · TTL index on carts · atomic single-document update.

**Index effect (`explain('executionStats')`) on order history for one customer:** COLLSCAN examined 30,000 documents to return 7; after compound index `{customer_id:1, order_date:-1}` an IXSCAN examined only 7 documents (see output file; timings are small at this data size, documents examined shows the difference).

## Suitability: when NoSQL fits NaijaMart – and when it doesn't
- **Good fit:** product catalogue with varied attributes, order documents read as a whole, session/cart data, high read volume, easy horizontal scaling (sharding).
- **Poor fit:** the financial core. Payments, stock decrement across many products, and refunds need multi-row ACID guarantees and referential integrity – these stay in PostgreSQL (Portfolio 3). MongoDB duplicates data (snapshots), so consistency of copied fields must be managed by the application.
- **Polyglot design:** PostgreSQL = system of record for orders/payments/stock; MongoDB = catalogue and read-optimised order views; key-value (TTL carts) for sessions. A graph database (e.g. Neo4j) could later power "customers who bought X also bought Y" recommendations – not implemented here.
