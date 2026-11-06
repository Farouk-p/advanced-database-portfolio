// Builds the LMS Word document. Run: NODE_PATH=<folder with docx installed> node build.js
const fs = require('fs');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, ShadingType, AlignmentType, LevelFormat } = require('docx');

const F = 'Calibri';
const run = x => typeof x === 'string' ? new TextRun({ text: x, font: F, size: 20 }) : x;
const p = (t, o = {}) => new Paragraph({ spacing: { after: 80 }, ...o, children: [].concat(t).map(run) });
const b = t => new TextRun({ text: t, bold: true, font: F, size: 20 });
const h = t => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun({ text: t, font: F })] });
const bullet = t => new Paragraph({ numbering: { reference: 'b', level: 0 }, spacing: { after: 40 }, children: [].concat(t).map(run) });

const W = [1500, 3300, 4226];
const cell = (t, i, head) => new TableCell({ width: { size: W[i], type: WidthType.DXA }, margins: { top: 40, bottom: 40, left: 80, right: 80 },
  shading: head ? { type: ShadingType.CLEAR, fill: 'D9E2F3', color: 'auto' } : undefined,
  children: [new Paragraph({ children: [new TextRun({ text: t, font: F, size: 18, bold: !!head })] })] });
const row = (a, head) => new TableRow({ children: a.map((t, i) => cell(t, i, head)) });

const table = new Table({ width: { size: 9026, type: WidthType.DXA }, columnWidths: W, rows: [
  row(['Portfolio', 'What I built', 'Main result'], true),
  row(['1 Design (7)', 'Farpoint schema: customers, accounts, deposits, withdrawals, transfers, transaction_logs; ER diagram; normalisation; 246,776 log rows of test data', 'Every account balance equals the sum of its log (audit: 0 mismatches)'], false),
  row(['2 Queries (7)', '8 bank queries including the balance audit; 7 indexes; plans before and after', 'Statement query 16.4 to 0.9 ms; reversed-transfers query 45 to 1.0 ms; whole-table queries correctly unchanged'], false),
  row(['3 Transactions (7)', 'Commit, rollback, reversal of a failed transfer, a safe transfer_funds() function; double-spend, deadlock and isolation-level demos', 'Unprotected race paid out N160,000 from a N100,000 account; row lock, atomic update and stricter isolation each stopped it'], false),
  row(['4 NoSQL (7)', 'MongoDB: transaction history (flexible details per type) and monthly statement buckets, loaded from PostgreSQL', 'MongoDB totals match PostgreSQL exactly; index cut documents examined from 246,776 to 25'], false),
  row(['5 Distributed (6)', 'PostgreSQL replica, sync vs async commits, promotion failover; 3-node MongoDB replica set; sharding key test; CAP discussion', 'Sync mode stopped writes when the replica was down; hash key spread rows 25% each, date key put all recent writes on one shard'], false),
] });

const doc = new Document({
  styles: { default: { document: { run: { font: F, size: 20 } } },
    paragraphStyles: [
      { id: 'Title', name: 'Title', basedOn: 'Normal', run: { font: F, size: 32, bold: true }, paragraph: { spacing: { after: 60 } } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { font: F, size: 24, bold: true, color: '1F3864' }, paragraph: { spacing: { before: 140, after: 60 }, keepNext: true } } ] },
  numbering: { config: [{ reference: 'b', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360, hanging: 240 } } } }] }] },
  sections: [{ properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1000, bottom: 1000, left: 1440, right: 1440 } } },
    children: [
      new Paragraph({ style: 'Title', children: [new TextRun({ text: 'MIT 8103 Advanced Database Systems: Portfolio Documentation', font: F })] }),
      p([b('Student: '), 'FULL NAME   ', b('Matric No: '), 'MATRIC NO   ', b('Session: '), '2026/2027 First Semester']),
      p([b('GitHub repository (private; assessor has access): '), 'PASTE GITHUB LINK HERE']),

      h('1. Selected case study: Farpoint (simulated bank / fintech)'),
      p('Farpoint is a made-up Nigerian digital bank. Its database holds customers, accounts, deposits, withdrawals, transfers and transaction logs. It is used by customers through a mobile app, by bank staff who help them, and by auditors. The three operations it must support are transferring funds, reversing failed transactions, and auditing account balances. I chose a bank because moving money safely is where transactions, concurrency and consistency matter most. The same case study is used in all five portfolios, with PostgreSQL for the money and MongoDB for the transaction history.'),

      h('2. Summary of the five portfolio activities'),
      table,

      h('3. What I did in each portfolio'),
      p([b('Portfolio 1: Design. '), 'Six tables with primary keys, foreign keys and checks that stop bad data at the database: amounts must be positive, balances cannot go negative, a transfer cannot go to the same account, and each log row must point to exactly one deposit, withdrawal or transfer. Normalisation went from a flat statement sheet to third normal form. Two deliberate shortcuts are stored copies: accounts.balance and the running balance_after in the log. They are safe only while every change happens inside a transaction.']),
      p([b('Portfolio 2: Query processing and optimisation. '), 'On 80,000 transfers and about 247,000 log rows, I compared execution plans before and after indexing. Queries that fetch a few rows gained most: a composite index on (account_id, created_at) took the statement query from 16.4 ms to 0.9 ms, and partial indexes on failed and reversed transfers made the reversal report about 45 times faster. Queries that read most of a table (top senders, the audit) kept their plan, because a full scan is cheaper there. My first timings were distorted by a cold cache, so I repeated them warm.']),
      p([b('Portfolio 3: Transactions and concurrency. '), 'A transfer commits the debit, credit and both log rows together. A transfer that breaks the balance rule rolls back completely. A failed transfer is reversed with a new REVERSAL entry, not a deletion, so the audit trail stays complete. With two real concurrent sessions, an unprotected double-spend approved N160,000 from a N100,000 account. A row lock, an atomic UPDATE with the check inside it, and REPEATABLE READ each prevented it. Opposite transfers caused a deadlock that PostgreSQL cancelled, and locking accounts in a fixed order avoids it. Write skew broke a two-account rule at REPEATABLE READ but was blocked at SERIALIZABLE.']),
      p([b('Portfolio 4: NoSQL. '), 'MongoDB suits the transaction history: it is written once, read in bulk, and its details differ by type (channel for cash, counterparty for transfers). I loaded all 246,776 log rows and built 112,486 monthly statement documents so one statement is a single read. The totals match PostgreSQL to the kobo. Balances and transfers stay relational because they need all-or-nothing updates across rows.']),
      p([b('Portfolio 5: Distributed and cloud. '), 'A PostgreSQL replica served reads and was about 1.4 seconds behind. In synchronous mode a commit took 169 ms, but with the replica down the commit hung: the bank trades availability for not losing confirmed money. Promoting the replica kept all test deposits. A 3-node MongoDB set elected a new primary on its own, and refused writes when only one node was left. Hashing the account number spread rows evenly across 4 shards; sharding by date sent all recent writes to one. The cloud part is a discussion of managed services, not a deployment.']),

      h('4. Individual technical reflection'),
      p('REPLACE WITH YOUR OWN WORDS (about 120 to 150 words). Ideas to cover: why a bank suited this course; a design decision you can defend (for example keeping balance_after, or reversing with a new entry instead of deleting); one thing that went wrong and how you fixed it (for example a cold-cache timing misled the first comparison, or a demo printed "approved" after the database had cancelled it); and what you learned (for example that the default isolation level is not enough for money, or that the shard key decides everything).'),

      h('5. Screenshots / evidence'),
      p('INSERT SCREENSHOTS HERE: (1) \\dt and the row counts; (2) Q1 plan before and after; (3) the double-spend run showing both ATMs approved; (4) the deadlock error; (5) the SERIALIZABLE cancellation; (6) Mongo explain before and after the index; (7) replica read-only error and the hung synchronous commit; (8) Mongo election after the primary stopped. The raw outputs are in each portfolio\'s evidence folder.'),

      h('6. References and AI Use Declaration'),
      bullet('PostgreSQL 16 documentation: EXPLAIN, Transaction Isolation, Explicit Locking, High Availability and Replication. postgresql.org/docs/16'),
      bullet('MongoDB Manual 7.0: Data Modeling, Aggregation, Replication, Sharding. mongodb.com/docs/manual'),
      bullet('Silberschatz, Korth and Sudarshan, Database System Concepts; Elmasri and Navathe, Fundamentals of Database Systems.'),
      p([b('AI Use Declaration. Tool: '), 'Claude (Anthropic) through Claude Code. ', b('Used for: '), 'drafting SQL, JavaScript and shell scripts, Docker configuration and README text. ', b('How I checked it: '), 'every script was run against the real databases and the evidence files are the actual outputs. I fixed problems found by running them, including a slow seed script, demo output that misreported cancelled transactions, and a cold-cache timing. I am responsible for the work and can explain it.'], { spacing: { before: 80, after: 0 } }),
    ] }] });

Packer.toBuffer(doc).then(buf => { fs.writeFileSync('Farpoint_Portfolio_Documentation.docx', buf); console.log('written', buf.length); });
