// NaijaMart document model (MongoDB 7). Run: mongosh naijamart 01_seed.js
db = db.getSiblingDB('naijamart');
db.dropDatabase();

const cities = ['Lagos','Abuja','Ibadan','Kano','Port Harcourt','Enugu'];
const phoneBrands = ['Tecno','Infinix','Samsung','Apple','Nokia'];
const laptopBrands = ['HP','Dell','Lenovo','Apple'];
const rnd = n => Math.floor(Math.random()*n);
const pick = a => a[rnd(a.length)];

// Products: attributes differ per category -> flexible schema (the main reason for a document store)
const products = [];
for (let i = 1; i <= 3000; i++) {
  const kind = pick(['phone','laptop','clothing','grocery']);
  const base = { _id: i, name: `Product ${i}`, category: kind, price: 500 + rnd(499500), stock: rnd(500),
                 tags: [kind, pick(['new','popular','sale'])], reviews: [] };
  if (kind === 'phone')    base.attributes = { brand: pick(phoneBrands), ram_gb: pick([2,4,6,8]), storage_gb: pick([32,64,128,256]), dual_sim: Math.random() < .6 };
  if (kind === 'laptop')   base.attributes = { brand: pick(laptopBrands), ram_gb: pick([8,16,32]), cpu: pick(['i3','i5','i7','Ryzen 5']), screen_in: pick([13.3,14,15.6]) };
  if (kind === 'clothing') base.attributes = { size: pick(['S','M','L','XL']), colour: pick(['red','blue','black','white']), material: pick(['cotton','linen','silk']) };
  if (kind === 'grocery')  base.attributes = { weight_g: pick([250,500,1000]), expiry: new Date(Date.now() + rnd(365)*864e5), perishable: Math.random() < .5 };
  // embedded reviews (bounded: max 5 per product) -> read product page with one query
  for (let r = 0, n = rnd(6); r < n; r++) base.reviews.push({ customer_id: 1 + rnd(5000), rating: 1 + rnd(5), comment: 'Nice', at: new Date() });
  products.push(base);
}
db.products.insertMany(products);

db.customers.insertMany(Array.from({length: 5000}, (_, k) => ({
  _id: k + 1, full_name: `Customer ${k+1}`, email: `customer${k+1}@mail.ng`,
  addresses: [{ street: `${rnd(200)} Market Rd`, city: pick(cities), is_default: true }] })));

// Orders embed line items (snapshot of name+price at purchase time) and payment + delivery:
// an order is always read/written as one unit -> one document = one atomic write
const orders = [];
for (let o = 1; o <= 30000; o++) {
  const items = Array.from({length: 1 + rnd(3)}, () => { const p = products[rnd(3000)];
    return { product_id: p._id, name: p.name, qty: 1 + rnd(4), unit_price: p.price }; });
  orders.push({ _id: o, customer_id: 1 + rnd(5000), status: pick(['PAID','SHIPPED','DELIVERED','DELIVERED','CANCELLED']),
    order_date: new Date(Date.now() - rnd(730)*864e5), items,
    total: items.reduce((s, i) => s + i.qty * i.unit_price, 0),
    payment: { method: pick(['CARD','TRANSFER','USSD']), status: 'SUCCESS' },
    delivery: { courier: pick(['GIG','Kwik','DHL']), city: pick(cities) } });
}
db.orders.insertMany(orders);

// Key-value style session carts (a Redis-like use: lookup by key, TTL expiry)
db.carts.insertOne({ _id: 'cart:1', customer_id: 1, items: [{ product_id: 5, qty: 1 }], updatedAt: new Date() });
db.carts.createIndex({ updatedAt: 1 }, { expireAfterSeconds: 3600 });
print('seeded: ' + db.products.countDocuments() + ' products, ' + db.customers.countDocuments() + ' customers, ' + db.orders.countDocuments() + ' orders');
