-- Indexes chosen after reading the "before" plans
CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date DESC);      -- Q1
CREATE INDEX idx_orders_delivered_date ON orders(order_date) WHERE status = 'DELIVERED'; -- Q2 (partial)
CREATE INDEX idx_orders_pending_date ON orders(order_date) WHERE status = 'PENDING';     -- Q7 (partial)
CREATE INDEX idx_order_items_product ON order_items(product_id) INCLUDE (quantity);      -- Q3, Q4, Q8 (covering)
CREATE INDEX idx_payments_order ON payments(order_id);                                   -- Q7 anti-join
CREATE INDEX idx_reviews_product ON reviews(product_id);                                 -- Q6
CREATE INDEX idx_products_lowstock ON products(product_id) WHERE stock_qty < 20;         -- Q8 (partial)
ANALYZE;
