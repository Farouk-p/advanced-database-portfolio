db = db.getSiblingDB('naijamart');
const t = (label, f) => { print('\n=== ' + label); printjson(f()); };

t('Q1 Flexible attributes: phones with >=8GB RAM, dual sim, under 300k', () =>
  db.products.find({ category: 'phone', 'attributes.ram_gb': { $gte: 8 }, 'attributes.dual_sim': true, price: { $lt: 300000 } },
                   { name: 1, price: 1, 'attributes.brand': 1 }).limit(3).toArray());

t('Q2 Product page in ONE read (product + embedded reviews)', () => db.products.findOne({ _id: 10 }));

t('Q3 Customer order history (embedded items, no joins)', () =>
  db.orders.find({ customer_id: 777 }, { order_date: 1, status: 1, total: 1, 'items.name': 1 }).sort({ order_date: -1 }).limit(3).toArray());

t('Q4 Aggregation: top 5 best-selling products', () => db.orders.aggregate([
  { $match: { status: { $ne: 'CANCELLED' } } }, { $unwind: '$items' },
  { $group: { _id: '$items.name', units: { $sum: '$items.qty' }, revenue: { $sum: { $multiply: ['$items.qty', '$items.unit_price'] } } } },
  { $sort: { units: -1 } }, { $limit: 5 }]).toArray());

t('Q5 Aggregation: revenue by delivery city', () => db.orders.aggregate([
  { $match: { status: 'DELIVERED' } }, { $group: { _id: '$delivery.city', revenue: { $sum: '$total' }, orders: { $sum: 1 } } },
  { $sort: { revenue: -1 } }]).toArray());

t('Q6 Average rating per category (unwind embedded reviews)', () => db.products.aggregate([
  { $unwind: '$reviews' }, { $group: { _id: '$category', avg: { $avg: '$reviews.rating' }, n: { $sum: 1 } } }, { $sort: { avg: -1 } }]).toArray());

// Index effect on Q3
const stat = () => { const e = db.orders.find({ customer_id: 777 }).sort({ order_date: -1 }).explain('executionStats').executionStats;
  return { stage_docs_examined: e.totalDocsExamined, returned: e.nReturned, ms: e.executionTimeMillis }; };
t('EXPLAIN before index (COLLSCAN)', stat);
db.orders.createIndex({ customer_id: 1, order_date: -1 });
db.products.createIndex({ category: 1, 'attributes.ram_gb': 1, price: 1 });
t('EXPLAIN after index (IXSCAN)', stat);

// Atomic single-document update (order status + delivery in one doc)
t('Update: mark order 1 delivered (single-document atomic write)', () =>
  db.orders.updateOne({ _id: 1 }, { $set: { status: 'DELIVERED', 'delivery.delivered_at': new Date() } }));
