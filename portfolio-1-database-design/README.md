# Portfolio 1 – Database Design and Modelling

## 1. Case study: NaijaMart (simulated e-commerce platform)
- **Nature of business:** online marketplace selling electronics, fashion, home and grocery items in Nigeria, with courier delivery.
- **Users of the database:** customers (browse/order), store admins (manage catalogue and stock), finance staff (payments/refunds), logistics staff (deliveries), analysts (sales reports).
- **Major data stored:** customers, addresses, categories, products, stock levels, orders, order items, payments, couriers, deliveries, product reviews.
- **Key operations:** register customer, add/update products, place order, decrement stock, record payment, assign delivery, track delivery, review product, produce sales reports.

## 2. ER diagram
See `er-diagram.md` (Mermaid; renders on GitHub) and `evidence/` for exported image.

## 3. Relational schema
`01_schema.sql` – 10 tables (customers, addresses, categories, products, orders, order_items, payments, couriers, deliveries, reviews) with:
- **Primary keys** (surrogate BIGSERIAL; composite PK `(order_id, product_id)` on order_items)
- **Foreign keys** with ON DELETE rules
- **Constraints:** NOT NULL, UNIQUE (email, one review per customer/product, one delivery per order), CHECK (price >= 0, stock >= 0, rating 1–5, status enumerations)

## 4. Normalisation
**Unnormalised order sheet:** `Order(order_id, order_date, customer_name, customer_email, customer_address, [product_name, category, price, qty]*, payment_method, courier_name)`.
- **1NF:** remove the repeating group of products → separate `order_items` row per product; atomic address fields (street, city, state).
- **2NF:** in `order_items(order_id, product_id, product_name, price, qty)`, `product_name`/`price` depend only on `product_id` (partial dependency) → moved to `products`. `unit_price` is kept deliberately in order_items as a *historical price snapshot* (it is not a dependency on product_id alone: it is the price at purchase time).
- **3NF:** remove transitive dependencies: customer details depend on `customer_id`, not `order_id` → `customers`; `category name` depends on `category_id` not `product_id` → `categories`; courier name depends on `courier_id` → `couriers`.
- **BCNF:** every determinant is a candidate key in all tables (e.g. `email` in customers is a candidate key).
- **Deliberate denormalisation:** `orders.total_amount` (derived, kept for fast reporting; maintained in the order transaction – see Portfolio 3).

## 5. Run
```bash
docker compose up -d          # creates schema + seed (~20k customers, 5k products, 150k orders)
docker exec -it naijamart-pg psql -U naija -d naijamart -c '\dt'
```
