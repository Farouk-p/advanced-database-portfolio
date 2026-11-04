-- Portfolio 2: queries used for optimisation (each is run with EXPLAIN (ANALYZE, BUFFERS))

-- Q1: Order history for one customer (selective filter + sort)
SELECT order_id, order_date, status, total_amount
FROM orders WHERE customer_id = 777 ORDER BY order_date DESC;

-- Q2: Revenue by month for delivered orders (aggregation + date filter)
SELECT date_trunc('month', order_date) AS month, SUM(total_amount) AS revenue, COUNT(*) AS orders
FROM orders
WHERE status = 'DELIVERED' AND order_date >= now() - interval '6 months'
GROUP BY 1 ORDER BY 1;

-- Q3: Top 10 best-selling products (multi-join + aggregate)
SELECT p.product_id, p.name, SUM(oi.quantity) AS units_sold
FROM order_items oi JOIN products p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.name ORDER BY units_sold DESC LIMIT 10;

-- Q4: Revenue per category and state (4-table join)
SELECT c.name AS category, a.state, SUM(oi.quantity*oi.unit_price) AS revenue
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
JOIN addresses a ON a.address_id = o.address_id
WHERE o.status <> 'CANCELLED'
GROUP BY c.name, a.state ORDER BY revenue DESC LIMIT 20;

-- Q5: Customers whose spend ranks in top 3 within their state (window function + CTE)
WITH spend AS (
  SELECT cu.customer_id, a.state, SUM(o.total_amount) AS total_spent
  FROM customers cu JOIN orders o ON o.customer_id = cu.customer_id
  JOIN addresses a ON a.address_id = o.address_id
  WHERE o.status <> 'CANCELLED' GROUP BY cu.customer_id, a.state)
SELECT * FROM (SELECT *, RANK() OVER (PARTITION BY state ORDER BY total_spent DESC) rnk FROM spend) r
WHERE rnk <= 3;

-- Q6: Average rating per product with at least 5 reviews (subquery/HAVING)
SELECT product_id, ROUND(AVG(rating),2) avg_rating, COUNT(*) n
FROM reviews GROUP BY product_id HAVING COUNT(*) >= 5 ORDER BY avg_rating DESC LIMIT 10;

-- Q7: Pending orders older than 30 days not yet paid (anti-join)
SELECT o.order_id, o.order_date FROM orders o
WHERE o.status = 'PENDING' AND o.order_date < now() - interval '30 days'
AND NOT EXISTS (SELECT 1 FROM payments p WHERE p.order_id = o.order_id);

-- Q8: Products low in stock that sold in the last 90 days
SELECT p.product_id, p.name, p.stock_qty
FROM products p
WHERE p.stock_qty < 20 AND p.product_id IN (
   SELECT oi.product_id FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
   WHERE o.order_date >= now() - interval '90 days');
