-- NaijaMart: e-commerce relational schema (PostgreSQL 16)
-- Portfolio 1: Database Design and Modelling

CREATE TABLE customers (
    customer_id   BIGSERIAL PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE addresses (
    address_id    BIGSERIAL PRIMARY KEY,
    customer_id   BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    street        VARCHAR(200) NOT NULL,
    city          VARCHAR(80)  NOT NULL,
    state         VARCHAR(80)  NOT NULL,
    is_default    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE categories (
    category_id        SERIAL PRIMARY KEY,
    name               VARCHAR(80) NOT NULL UNIQUE,
    parent_category_id INT REFERENCES categories(category_id)
);

CREATE TABLE products (
    product_id    BIGSERIAL PRIMARY KEY,
    category_id   INT NOT NULL REFERENCES categories(category_id),
    name          VARCHAR(150) NOT NULL,
    description   TEXT,
    price         NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    stock_qty     INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    order_id      BIGSERIAL PRIMARY KEY,
    customer_id   BIGINT NOT NULL REFERENCES customers(customer_id),
    address_id    BIGINT NOT NULL REFERENCES addresses(address_id),
    status        VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                  CHECK (status IN ('PENDING','PAID','SHIPPED','DELIVERED','CANCELLED')),
    total_amount  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    order_date    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
    order_id      BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    product_id    BIGINT NOT NULL REFERENCES products(product_id),
    quantity      INT NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE payments (
    payment_id    BIGSERIAL PRIMARY KEY,
    order_id      BIGINT NOT NULL REFERENCES orders(order_id),
    method        VARCHAR(20) NOT NULL CHECK (method IN ('CARD','TRANSFER','USSD','WALLET','COD')),
    amount        NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status        VARCHAR(20) NOT NULL CHECK (status IN ('SUCCESS','FAILED','REFUNDED')),
    paid_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE couriers (
    courier_id    SERIAL PRIMARY KEY,
    name          VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE deliveries (
    delivery_id   BIGSERIAL PRIMARY KEY,
    order_id      BIGINT NOT NULL UNIQUE REFERENCES orders(order_id),
    courier_id    INT NOT NULL REFERENCES couriers(courier_id),
    status        VARCHAR(20) NOT NULL CHECK (status IN ('ASSIGNED','IN_TRANSIT','DELIVERED','FAILED')),
    shipped_at    TIMESTAMPTZ,
    delivered_at  TIMESTAMPTZ
);

CREATE TABLE reviews (
    review_id     BIGSERIAL PRIMARY KEY,
    product_id    BIGINT NOT NULL REFERENCES products(product_id),
    customer_id   BIGINT NOT NULL REFERENCES customers(customer_id),
    rating        SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment       TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, customer_id)
);
