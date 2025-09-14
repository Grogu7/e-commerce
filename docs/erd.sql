CREATE TABLE "users" (
  "id" bigint PRIMARY KEY,
  "nickname" varchar,
  "created_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "wallets" (
  "user_id" bigint PRIMARY KEY,
  "balance" numeric(12,2),
  "updated_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "wallet_topup_history" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigint,
  "amount" numeric(12,2),
  "method" varchar,
  "ext_ref" varchar,
  "created_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "products" (
  "id" bigserial PRIMARY KEY,
  "name" varchar,
  "price" numeric(12,2),
  "stock" int,
  "is_active" boolean,
  "updated_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "orders" (
  "id" bigserial PRIMARY KEY,
  "user_id" bigint,
  "total_price" numeric(12,2),
  "discounted_price" numeric(12,2),
  "status" varchar,
  "created_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "order_items" (
  "id" bigserial PRIMARY KEY,
  "order_id" bigint,
  "product_id" bigint,
  "unit_price" numeric(12,2),
  "quantity" int,
  "line_total" numeric(12,2),
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "payments" (
  "id" bigserial PRIMARY KEY,
  "order_id" bigint UNIQUE,
  "method" varchar,
  "provider" varchar,
  "tx_id" varchar,
  "status" varchar,
  "paid_at" timestamptz,
  "failure_reason" text,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "coupon_batches" (
  "id" bigserial PRIMARY KEY,
  "name" varchar,
  "discount_type" varchar,
  "discount_value" numeric(12,2),
  "max_count" int,
  "starts_at" timestamptz,
  "ends_at" timestamptz,
  "enabled" boolean,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "coupons" (
  "id" bigserial PRIMARY KEY,
  "batch_id" bigint,
  "claimed_by" bigint,
  "code" varchar UNIQUE,
  "claimed_at" timestamptz,
  "expires_at" timestamptz,
  "used" boolean,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

CREATE TABLE "order_outbox_event" (
  "id" bigserial PRIMARY KEY,
  "order_id" bigint,
  "event_type" varchar,
  "payload_json" jsonb,
  "status" varchar,
  "retry_count" int,
  "next_retry_at" timestamptz,
  "created_at" timestamptz,
  "create_dtm" timestamptz,
  "create_id" varchar,
  "update_dtm" timestamptz,
  "update_sid" varchar
);

ALTER TABLE "wallets" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "wallet_topup_history" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "orders" ADD FOREIGN KEY ("user_id") REFERENCES "users" ("id");

ALTER TABLE "order_items" ADD FOREIGN KEY ("order_id") REFERENCES "orders" ("id");

ALTER TABLE "order_items" ADD FOREIGN KEY ("product_id") REFERENCES "products" ("id");

ALTER TABLE "payments" ADD FOREIGN KEY ("order_id") REFERENCES "orders" ("id");

ALTER TABLE "coupons" ADD FOREIGN KEY ("batch_id") REFERENCES "coupon_batches" ("id");

ALTER TABLE "coupons" ADD FOREIGN KEY ("claimed_by") REFERENCES "users" ("id");

ALTER TABLE "order_outbox_event" ADD FOREIGN KEY ("order_id") REFERENCES "orders" ("id");
