// Loads the exported transaction log into MongoDB and builds a monthly statement collection.
// Run:  docker cp data/transactions.jsonl farpoint-mongo:/tmp/ && docker cp 01_load.js farpoint-mongo:/tmp/
//       docker exec farpoint-mongo mongosh --quiet /tmp/01_load.js
const fs = require('fs');
db = db.getSiblingDB('farpoint');
db.dropDatabase();

// 1) transactions: one document per balance change.
//    "details" differs by transaction type (cash movements have a channel, transfers have a counterparty),
//    which is easy in a document store and awkward in a single relational table.
const lines = fs.readFileSync('/tmp/transactions.jsonl', 'utf8').split('\n').filter(Boolean);
let batch = [];
for (const line of lines) {
  const r = JSON.parse(line);
  const details = {};
  for (const [k, v] of Object.entries(r.details)) if (v !== null) details[k] = v;   // drop empty fields
  batch.push({
    _id: r.log_id,
    account_number: r.account_number,
    customer: { id: r.customer_id, name: r.customer_name },
    type: r.type, direction: r.direction,
    amount: Decimal128.fromString(r.amount),
    balance_after: Decimal128.fromString(r.balance_after),
    at: new Date(r.at),
    details
  });
  if (batch.length === 10000) { db.transactions.insertMany(batch); batch = []; }
}
if (batch.length) db.transactions.insertMany(batch);
print('transactions loaded: ' + db.transactions.countDocuments());

// 2) statements: one document per account per month (the "bucket" pattern).
//    A customer opens a monthly statement with ONE read instead of scanning hundreds of small documents.
db.transactions.aggregate([
  { $sort: { at: 1, _id: 1 } },
  { $group: {
      _id: { account_number: '$account_number', month: { $dateToString: { format: '%Y-%m', date: '$at' } } },
      customer: { $first: '$customer' },
      entries: { $push: { at: '$at', type: '$type', direction: '$direction', amount: '$amount', balance_after: '$balance_after' } },
      closing_balance: { $last: '$balance_after' },
      tx_count: { $sum: 1 } } },
  { $project: { _id: 0, account_number: '$_id.account_number', month: '$_id.month', customer: 1, entries: 1, closing_balance: 1, tx_count: 1 } },
  { $out: 'statements' }
], { allowDiskUse: true });
print('monthly statements built: ' + db.statements.countDocuments());
