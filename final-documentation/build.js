const fs = require('fs');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, ShadingType, AlignmentType, LevelFormat } = require('docx');

const F = 'Calibri';
const p = (t, o = {}) => new Paragraph({ spacing: { after: 80 }, ...o, children: [].concat(t).map(x => typeof x === 'string' ? new TextRun({ text: x, font: F, size: 20 }) : x) });
const b = t => new TextRun({ text: t, bold: true, font: F, size: 20 });
const h = t => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, font: F })] });
const bullet = t => new Paragraph({ numbering: { reference: 'b', level: 0 }, spacing: { after: 40 }, children: [].concat(t).map(x => typeof x === 'string' ? new TextRun({ text: x, font: F, size: 20 }) : x) });

const W = [1700, 3000, 4326]; // sum 9026 (A4 with 2cm margins ~ 9900; keep inside)
const cell = (t, i, head) => new TableCell({ width: { size: W[i], type: WidthType.DXA }, margins: { top: 40, bottom: 40, left: 80, right: 80 },
  shading: head ? { type: ShadingType.CLEAR, fill: 'D9E2F3', color: 'auto' } : undefined,
  children: [new Paragraph({ children: [new TextRun({ text: t, font: F, size: 18, bold: !!head })] })] });
const row = (a, head) => new TableRow({ children: a.map((t, i) => cell(t, i, head)) });

const table = new Table({ width: { size: 9026, type: WidthType.DXA }, columnWidths: W, rows: [
  row(['Portfolio', 'What was built', 'Key evidence / result'], true),
  row(['1 Design (7)', 'NaijaMart schema: 10 tables, PK/FK/CHECK/UNIQUE; ER diagram; normalisation UNF→3NF/BCNF; 150k-order seed', 'er-diagram.md, 01_schema.sql, evidence/row_counts.txt'], false),
  row(['2 Query opt. (7)', '8 queries (joins, CTE, window, anti-join) analysed with EXPLAIN (ANALYZE, BUFFERS); composite, partial and covering indexes', 'Q1 13.8→0.24 ms (Seq→Index scan); Q8 62→23 ms; full-table aggregates (Q3–Q6) correctly stayed Seq Scan'], false),
  row(['3 Transactions (7)', 'COMMIT/ROLLBACK/SAVEPOINT order flow; two real concurrent sessions', 'Lost update: stock 96 instead of 93; fixed by SELECT FOR UPDATE (93); REPEATABLE READ → serialization error; deadlock detected'], false),
  row(['4 NoSQL (7)', 'MongoDB: products with variable attributes + embedded reviews, orders with embedded items/payment/delivery, TTL carts', 'Aggregation pipelines; index cut docs examined 30,000 → 7'], false),
  row(['5 Distributed (6)', 'PostgreSQL streaming replica; 3-node MongoDB replica set; sharding and CAP discussion', 'Replica read-only, lag ≈2.4 s; primary killed → new primary elected, no data lost, old node rejoined'], false),
] });

const doc = new Document({
  styles: { default: { document: { run: { font: F, size: 20 } } },
    paragraphStyles: [
      { id: 'Title', name: 'Title', basedOn: 'Normal', run: { font: F, size: 32, bold: true }, paragraph: { spacing: { after: 60 } } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: F, size: 24, bold: true, color: '1F3864' }, paragraph: { spacing: { before: 140, after: 60 }, keepNext: true } } ] },
  numbering: { config: [{ reference: 'b', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360, hanging: 240 } } } }] }] },
  sections: [{ properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1000, bottom: 1000, left: 1440, right: 1440 } } },
    children: [
      new Paragraph({ style: 'Title', children: [new TextRun({ text: 'MIT 8103 Advanced Database Systems – Portfolio Documentation', font: F })] }),
      p([b('Student: '), 'FULL NAME  |  ', b('Matric No: '), 'MATRIC NO  |  ', b('Session: '), '2026/2027 First Semester']),
      p([b('GitHub repository (private; assessor has access): '), 'PASTE GITHUB LINK HERE']),

      h('1. Selected case study: NaijaMart (simulated e-commerce platform)'),
      p('NaijaMart is a simulated Nigerian online marketplace selling electronics, fashion, home and grocery items with courier delivery. The database is used by customers (browse and order), store admins (catalogue and stock), finance (payments and refunds), logistics (deliveries) and analysts (sales reports). Major data: customers, addresses, categories, products, stock, orders, order items, payments, couriers, deliveries and reviews. Key operations: register, place order, decrement stock, pay, assign and track delivery, review, and report. The same case study is used in all five portfolios. Stack: PostgreSQL 16 and MongoDB 7 in Docker.'),

      h('2. Summary of portfolio activities'),
      table,

      h('3. Portfolio details'),
      p([b('Portfolio 1 – Design. '), 'The schema uses surrogate keys, a composite key on order_items, foreign keys and CHECK constraints (price ≥ 0, stock ≥ 0, rating 1–5, status lists). Normalisation: repeating product groups were moved to order_items (1NF); product name/price moved out of order_items (2NF); customer, category and courier details moved to their own tables (3NF). Two deliberate choices: order_items.unit_price keeps the price at purchase time, and orders.total_amount is a controlled denormalisation for fast reporting.']),
      p([b('Portfolio 2 – Query optimisation. '), 'With 150,000 orders and about 300,000 order items, plans were captured before and after indexing. Selective queries gained most: a composite index (customer_id, order_date DESC) turned a Seq Scan into an index scan and removed the sort (Q1, about 58x faster). Partial indexes (e.g. WHERE status=\'PENDING\') are smaller and target specific queries. Queries that aggregate most of a table (Q3–Q6) did not change plan, since a sequential scan is cheaper there; a materialised summary table would be the next step. Indexes cost write performance, so only measured ones were kept.']),
      p([b('Portfolio 3 – Transactions. '), 'An order is atomic: a failed stock CHECK rolled back the order row too, and a SAVEPOINT let a failed payment be undone without losing the order. Two concurrent sessions reproduced a lost update at READ COMMITTED (stock 96 instead of 93). SELECT … FOR UPDATE fixed it (93), and REPEATABLE READ made the second writer fail with a serialization error that the application must retry. A non-repeatable read was shown at READ COMMITTED (price 1000→2000) and prevented at REPEATABLE READ. A deadlock from opposite lock order was detected by PostgreSQL; the fix is a consistent lock order.']),
      p([b('Portfolio 4 – NoSQL. '), 'Documents suit the catalogue because phones, clothes and groceries need different attributes. Reviews (bounded) are embedded, so a product page is one read. Orders embed items, payment and delivery, giving one atomic write and no joins. Orders reference customers and products by id because those are shared and change over time. Carts use a key-value style with a TTL index. NoSQL is not used for payments or stock, which need multi-row ACID guarantees and stay in PostgreSQL.']),
      p([b('Portfolio 5 – Distributed. '), 'A PostgreSQL streaming replica (asynchronous) served reads while rejecting writes; the measured lag shows why reads right after checkout should go to the primary. In a 3-node MongoDB replica set the primary was stopped: a new primary was elected, majority-written data survived, and the old node rejoined as secondary. Design discussion covers hashed shard keys (customer_id for orders to avoid hot shards), CAP/PACELC per component (money and stock need consistency, catalogue browsing tolerates staleness) and managed-cloud equivalents (RDS/Aurora, Atlas). A managed-cloud deployment was not performed; the cloud part is a discussion.']),

      h('4. Individual technical reflection'),
      p('REPLACE WITH YOUR OWN WORDS (about 120–150 words): why you chose e-commerce, one design decision you would defend (e.g. embedding vs referencing, or keeping unit_price in order_items), one challenge you hit (e.g. the first seed script was far too slow because it sorted 5,000 products per order, and I rewrote it to pick random ids), and what you learned (e.g. indexes do not help queries that scan most of a table; isolation levels trade anomalies for retries).'),

      h('5. Screenshots / evidence'),
      p('INSERT SCREENSHOTS HERE: (1) \\dt output, (2) EXPLAIN before/after for Q1, (3) lost-update run showing 96 vs 93, (4) deadlock error, (5) Mongo explain COLLSCAN vs IXSCAN, (6) replica read-only error, (7) Mongo failover election. Source outputs are in each portfolio\'s evidence/ folder.'),

      h('6. References and AI Use Declaration'),
      bullet('PostgreSQL 16 Documentation: EXPLAIN, Transaction Isolation, Streaming Replication, Explicit Locking. postgresql.org/docs/16'),
      bullet('MongoDB Manual 7.0: Data Modeling, Aggregation, Replication, Sharding. mongodb.com/docs/manual'),
      bullet('Silberschatz, Korth and Sudarshan, Database System Concepts; Elmasri and Navathe, Fundamentals of Database Systems.'),
      p([b('AI Use Declaration. Tool: '), 'Claude (Anthropic) via Claude Code. ', b('Used for: '), 'drafting SQL/JS/shell scripts, Docker configuration and README text. ', b('Verification: '), 'every script was run against the live databases and the evidence files are the real outputs; a slow seed script was found and fixed by running it; analysis was checked against the actual execution plans. I am responsible for understanding and can explain all submitted work.'], { spacing: { before: 80, after: 0 } }),
    ] }] });

Packer.toBuffer(doc).then(buf => { fs.writeFileSync('NaijaMart_Portfolio_Documentation.docx', buf); console.log('written', buf.length); });
