-- Demo 1: place an order atomically (COMMIT), fail mid-way (ROLLBACK), partial rollback (SAVEPOINT)
\echo '--- stock before'
SELECT product_id, stock_qty FROM products WHERE product_id IN (1,2);

\echo '--- A) successful order: COMMIT'
BEGIN;
WITH o AS (INSERT INTO orders(customer_id,address_id,status,total_amount) VALUES (1,1,'PAID',0) RETURNING order_id)
INSERT INTO order_items(order_id,product_id,quantity,unit_price)
  SELECT o.order_id, 1, 2, price FROM o, products WHERE product_id = 1;
UPDATE products SET stock_qty = stock_qty - 2 WHERE product_id = 1;
UPDATE orders SET total_amount = (SELECT SUM(quantity*unit_price) FROM order_items WHERE order_id = currval('orders_order_id_seq'))
  WHERE order_id = currval('orders_order_id_seq');
COMMIT;
SELECT product_id, stock_qty FROM products WHERE product_id = 1;

\echo '--- B) failing order: stock would go negative -> CHECK violation -> ROLLBACK'
BEGIN;
INSERT INTO orders(customer_id,address_id,status,total_amount) VALUES (1,1,'PAID',100);
UPDATE products SET stock_qty = stock_qty - 100000 WHERE product_id = 2;   -- violates CHECK (stock_qty >= 0)
ROLLBACK;
\echo 'orders row inserted in failed tx is gone (count of orders with total 100 and customer 1 created now):'
SELECT count(*) FROM orders WHERE customer_id=1 AND total_amount=100 AND order_date > now() - interval '1 minute';
SELECT product_id, stock_qty FROM products WHERE product_id = 2;

\echo '--- C) SAVEPOINT: payment fails, order kept as PENDING'
BEGIN;
INSERT INTO orders(customer_id,address_id,status,total_amount) VALUES (1,1,'PENDING',500) RETURNING order_id \gset
SAVEPOINT before_payment;
INSERT INTO payments(order_id,method,amount,status) VALUES (:order_id,'CARD',-5,'FAILED');  -- CHECK amount > 0 fails
ROLLBACK TO SAVEPOINT before_payment;
INSERT INTO payments(order_id,method,amount,status) VALUES (:order_id,'CARD',500,'FAILED');
COMMIT;
SELECT o.order_id, o.status, p.status AS payment_status FROM orders o JOIN payments p USING(order_id) WHERE o.order_id = :order_id;
