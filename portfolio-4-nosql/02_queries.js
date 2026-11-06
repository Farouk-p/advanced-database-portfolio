// Queries for the Farpoint document model. Run:
//   docker cp 02_queries.js farpoint-mongo:/tmp/ && docker exec farpoint-mongo mongosh --quiet /tmp/02_queries.js
db = db.getSiblingDB('farpoint');
const show = (title, f) => { print('\n=== ' + title); printjson(f()); };
const acct = '3000011111';   // a sample account

// Q1: statement for one account, newest 5 lines
show('Q1 Statement for one account (newest 5)', () =>
  db.transactions.find({ account_number: acct }, { _id: 0, at: 1, type: 1, direction: 1, amount: 1, balance_after: 1 })
    .sort({ at: -1 }).limit(5).toArray());

// Q2: the same customer reading a whole month from the statement bucket: ONE document
show('Q2 Monthly statement from the bucket (one document)', () => {
  const m = db.statements.find({ account_number: acct }).sort({ month: -1 }).limit(1).toArray()[0];
  return { account_number: m.account_number, month: m.month, customer: m.customer.name, transactions: m.tx_count, closing_balance: m.closing_balance, first_entry: m.entries[0] };
});

// Q3: flexible details: ATM withdrawals only (the "channel" field exists only on cash movements)
show('Q3 Count of withdrawals by channel (details differ by transaction type)', () =>
  db.transactions.aggregate([{ $match: { type: 'WITHDRAWAL' } }, { $group: { _id: '$details.channel', n: { $sum: 1 }, total: { $sum: '$amount' } } }, { $sort: { n: -1 } }]).toArray());

// Q4: failed and reversed transfers by reason (from the transfer details)
show('Q4 Reversals by reason', () =>
  db.transactions.aggregate([{ $match: { type: 'REVERSAL' } }, { $group: { _id: '$details.failure_reason', n: { $sum: 1 }, value: { $sum: '$amount' } } }]).toArray());

// Q5: daily money movement, last 30 days of data
show('Q5 Daily volume by type, last 5 days of data', () => {
  const last = db.transactions.find().sort({ at: -1 }).limit(1).toArray()[0].at;
  const from = new Date(last.getTime() - 30 * 864e5);
  return db.transactions.aggregate([{ $match: { at: { $gte: from } } },
    { $group: { _id: { day: { $dateToString: { format: '%Y-%m-%d', date: '$at' } }, type: '$type' }, n: { $sum: 1 }, total: { $sum: '$amount' } } },
    { $sort: { '_id.day': -1, '_id.type': 1 } }, { $limit: 5 }]).toArray();
});

// Q6: top 5 senders by total transferred out
show('Q6 Top 5 senders', () =>
  db.transactions.aggregate([{ $match: { type: 'TRANSFER_OUT' } },
    { $group: { _id: { account: '$account_number', name: '$customer.name' }, sent: { $sum: '$amount' } } },
    { $sort: { sent: -1 } }, { $limit: 5 }]).toArray());

// Index effect on Q1, measured with explain
const stats = () => { const e = db.transactions.find({ account_number: acct }).sort({ at: -1 }).limit(50).explain('executionStats').executionStats;
  return { docs_examined: e.totalDocsExamined, docs_returned: e.nReturned, millis: e.executionTimeMillis }; };
show('Q1 explain BEFORE index (reads the whole collection)', stats);
db.transactions.createIndex({ account_number: 1, at: -1 });
db.statements.createIndex({ account_number: 1, month: -1 });
show('Q1 explain AFTER index {account_number, at}', stats);

// Cross-check against PostgreSQL (the PostgreSQL totals are shown in the README)
show('Cross-check: collection totals', () => ({
  transactions: db.transactions.countDocuments(),
  credits: db.transactions.aggregate([{ $match: { direction: 'CREDIT' } }, { $group: { _id: null, t: { $sum: '$amount' } } }]).toArray()[0].t,
  debits:  db.transactions.aggregate([{ $match: { direction: 'DEBIT' } },  { $group: { _id: null, t: { $sum: '$amount' } } }]).toArray()[0].t }));
