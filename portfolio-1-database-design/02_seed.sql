-- Synthetic seed data (deterministic via setseed) so Portfolio 2 has realistic volume.
SELECT setseed(0.42);

INSERT INTO categories(name, parent_category_id) VALUES
 ('Electronics',NULL),('Fashion',NULL),('Home & Kitchen',NULL),('Groceries',NULL),
 ('Phones',1),('Laptops',1),('Men Clothing',2),('Women Clothing',2),('Appliances',3),('Beverages',4);

INSERT INTO couriers(name) VALUES ('GIG Logistics'),('Kwik Delivery'),('DHL Nigeria'),('Sendbox');

INSERT INTO customers(full_name,email,phone,created_at)
SELECT 'Customer '||g, 'customer'||g||'@mail.ng', '080'||lpad((random()*99999999)::int::text,8,'0'),
       now() - (random()*730||' days')::interval
FROM generate_series(1,20000) g;

INSERT INTO addresses(customer_id,street,city,state,is_default)
SELECT c, (random()*200)::int||' Market Rd',
       (ARRAY['Lagos','Abuja','Ibadan','Kano','Port Harcourt','Enugu'])[1+(random()*5)::int],
       (ARRAY['Lagos','FCT','Oyo','Kano','Rivers','Enugu'])[1+(random()*5)::int], TRUE
FROM generate_series(1,20000) c;

INSERT INTO products(category_id,name,description,price,stock_qty,created_at)
SELECT 5+(random()*5)::int, 'Product '||g, 'Description of product '||g,
       round((500+random()*499500)::numeric,2), (random()*500)::int,
       now() - (random()*730||' days')::interval
FROM generate_series(1,5000) g;

INSERT INTO orders(customer_id,address_id,status,total_amount,order_date)
SELECT c, c,
       (ARRAY['PENDING','PAID','SHIPPED','DELIVERED','DELIVERED','DELIVERED','CANCELLED'])[1+(random()*6)::int],
       0, now() - (random()*730||' days')::interval
FROM (SELECT 1+(random()*19999)::int AS c FROM generate_series(1,150000)) t;

-- 1 to 3 products per order (random product ids; duplicates within an order are skipped)
INSERT INTO order_items(order_id,product_id,quantity,unit_price)
SELECT t.order_id, p.product_id, 1+(random()*4)::int, p.price
FROM (
  SELECT o.order_id, 1 + (floor(random()*5000))::int AS pid
  FROM orders o CROSS JOIN LATERAL generate_series(1, 1 + (o.order_id % 3)) k
) t
JOIN products p ON p.product_id = t.pid
ON CONFLICT (order_id, product_id) DO NOTHING;

UPDATE orders o SET total_amount = s.t
FROM (SELECT order_id, SUM(quantity*unit_price) t FROM order_items GROUP BY order_id) s
WHERE s.order_id = o.order_id;

INSERT INTO payments(order_id,method,amount,status,paid_at)
SELECT order_id,
       (ARRAY['CARD','TRANSFER','USSD','WALLET','COD'])[1+(random()*4)::int],
       GREATEST(total_amount,1),
       CASE WHEN status='CANCELLED' THEN 'FAILED' ELSE 'SUCCESS' END, order_date
FROM orders WHERE status <> 'PENDING';

INSERT INTO deliveries(order_id,courier_id,status,shipped_at,delivered_at)
SELECT order_id, 1+(random()*3)::int,
       CASE WHEN status='DELIVERED' THEN 'DELIVERED' ELSE 'IN_TRANSIT' END,
       order_date + interval '1 day',
       CASE WHEN status='DELIVERED' THEN order_date + interval '3 days' END
FROM orders WHERE status IN ('SHIPPED','DELIVERED');

INSERT INTO reviews(product_id,customer_id,rating,comment)
SELECT DISTINCT ON (product_id,customer_id) product_id, customer_id, 1+(random()*4)::int, 'Review text'
FROM (SELECT 1+(random()*4999)::int product_id, 1+(random()*19999)::int customer_id
      FROM generate_series(1,40000)) r;

ANALYZE;
