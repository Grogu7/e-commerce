# Data Model Spec — Ecommerce Ordering (v1)

> 목적: API 명세를 뒷받침하는 **테이블 설계** 정리.

## 0. 스키마 개요
- **DB**: PostgreSQL
- **명명 규칙**: 스네이크 케이스

---

## 1. 테이블 사전 (Data Dictionary)

### 1.1 `users`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 사용자 ID |
| `name` | TEXT | NOT NULL | 표시 이름 |
| `created_at` | TIMESTAMP | NOT NULL DEFAULT now() | 생성 시각 |

인덱스: 필요 시 `name` 검색 인덱스 추가.

---

### 1.2 `wallets`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `user_id` | BIGINT | PK, FK → users(id) | 사용자 ID(=지갑 키) |
| `balance` | BIGINT | NOT NULL DEFAULT 0 | 보유 잔액(원) |
| `updated_at` | TIMESTAMP |  | 최근 변경 시각 |

인덱스: PK(user_id)

**비즈니스 규칙**
- balance ≥ 0 유지. 음수 불가.
- 충전: `balance = balance + :amount` (amount ≥ 1)
- 차감: `WHERE balance >= :amount` 조건부 UPDATE 쿼리로 음수 잔액 음수 방지 필요

---

### 1.3 `products`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 상품 ID |
| `name` | TEXT | NOT NULL | 상품명 |
| `price` | BIGINT | NOT NULL | 단가(원) |
| `stock` | INT | NOT NULL | 재고 수량(0 이상) |
| `created_at` | TIMESTAMP | NOT NULL DEFAULT now() | 생성 시각 |
| `updated_at` | TIMESTAMP |  | 갱신 시각 |

인덱스: PK(id), (updated_at)

**비즈니스 규칙**
- 재고 차감: `WHERE stock >= :qty` 조건부 UPDATE로 재고 음수 방지. (* 비즈니스 로직에 따라 음수 재고 허용가능 할지?)

---

### 1.4 `coupon_batches`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 배치 ID |
| `name` | TEXT | NOT NULL | 배치명(관리용) |
| `discount_type` | TEXT | NOT NULL CHECK in('PERCENT','FLAT') | 할인 유형 |
| `discount_value` | BIGINT | NOT NULL | 할인 값 (PERCENT=0..100, FLAT=원) |
| `max_issuance` | INT | NOT NULL | 최대 발급 수량 |
| `expires_at` | TIMESTAMP |  | 만료 시각(옵션) |
| `created_at` | TIMESTAMP | NOT NULL DEFAULT now() | 생성 시각 |

인덱스: PK(id)

---

### 1.5 `coupons`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 쿠폰 ID |
| `batch_id` | BIGINT | FK → coupon_batches(id) | 배치 참조 |
| `code` | TEXT | UNIQUE NOT NULL | 외부 노출 코드 |
| `claimed_by` | BIGINT | FK → users(id) NULLABLE | 소유자 |
| `claimed_at` | TIMESTAMP |  | 발급 시각 |
| `used_at` | TIMESTAMP |  | 사용 시각 |
| `order_id` | BIGINT |  | 사용된 주문 ID(정보용) |

인덱스: (batch_id), (claimed_by)

**제약/정책**
- **1인 1매**: 파샬 유니크(대안) → `UNIQUE (batch_id, claimed_by) WHERE claimed_by IS NOT NULL`
- 발급: 미소유 쿠폰을 `FOR UPDATE SKIP LOCKED`로 선점 → `claimed_by/claimed_at` 세팅
- 사용: 주문 성공 시 `used_at`, `order_id` 세팅

---

### 1.6 `orders`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 주문 ID |
| `user_id` | BIGINT | FK → users(id) | 주문자 |
| `total_price` | BIGINT | NOT NULL | 총액(할인 전) |
| `discount_applied` | BIGINT | NOT NULL | 할인액 |
| `final_price` | BIGINT | NOT NULL | 결제액(≥0) |
| `status` | TEXT | NOT NULL | 'PAID'|'CANCELED'|'FAILED' |'RESERVED'|
| `idempotency_key` | TEXT | UNIQUE NOT NULL | 멱등성 키 |
| `paid_at` | TIMESTAMP |  | 결제 시각 |
| `created_at` | TIMESTAMP | NOT NULL DEFAULT now() | 생성 시각 |

인덱스: (paid_at, status)
status 컬럼은 서버 소스상에서 ENUM으로 관리 필요.
PAID: 실제 결재까지 완료
RESERVED: 주문 완료
---

### 1.7 `order_items`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 아이템 ID |
| `order_id` | BIGINT | FK → orders(id) | 주문 참조 |
| `product_id` | BIGINT | FK → products(id) | 상품 참조 |
| `quantity` | INT | NOT NULL | 수량(≥1) |
| `unit_price` | BIGINT | NOT NULL | 주문 시 단가(스냅샷) |

인덱스: (order_id), (product_id)

---
### 1.8 `outbox_event`
| 컬럼 | 타입 | 제약 | 설명 |
|---|---|---|---|
| `id` | BIGSERIAL | PK | 이벤트 ID |
| `event_type` | TEXT | NOT NULL | 예: 'ORDER_PAID' |
| `payload_json` | JSONB | NOT NULL | 전송 페이로드 |
| `status` | TEXT | NOT NULL | 'PENDING'|'SENT'|'FAILED' |
| `retry_count` | INT | NOT NULL DEFAULT 0 | 재시도 횟수 |
| `next_retry_at` | TIMESTAMP |  | 다음 재시도 시각 |
| `created_at` | TIMESTAMP | NOT NULL DEFAULT now() | 생성 시각 |

인덱스: (status, next_retry_at)
status, event_type 컬럼은 서버 소스상에서 ENUM으로 관리 필요.

 
---

## 2. DDL
```sql
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE wallets (
  user_id BIGINT PRIMARY KEY REFERENCES users(id),
  balance BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMP
);

CREATE TABLE products (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  price BIGINT NOT NULL,
  stock INT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP
);

CREATE TABLE coupon_batches (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('PERCENT','FLAT')),
  discount_value BIGINT NOT NULL,
  max_issuance INT NOT NULL,
  expires_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE coupons (
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES coupon_batches(id),
  code TEXT NOT NULL UNIQUE,
  claimed_by BIGINT REFERENCES users(id),
  claimed_at TIMESTAMP,
  used_at TIMESTAMP,
  order_id BIGINT
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_coupons_batch_user
  ON coupons(batch_id, claimed_by) WHERE claimed_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_coupons_batch ON coupons(batch_id);
CREATE INDEX IF NOT EXISTS ix_coupons_claimed_by ON coupons(claimed_by);

CREATE TABLE orders (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  total_price BIGINT NOT NULL,
  discount_applied BIGINT NOT NULL,
  final_price BIGINT NOT NULL,
  status TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  paid_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_orders_paid_status ON orders(paid_at, status);

CREATE TABLE order_items (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  product_id BIGINT NOT NULL REFERENCES products(id),
  quantity INT NOT NULL,
  unit_price BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS ix_order_items_product ON order_items(product_id);

CREATE TABLE outbox_event (
  id BIGSERIAL PRIMARY KEY,
  event_type TEXT NOT NULL,
  payload_json JSONB NOT NULL,
  status TEXT NOT NULL,
  retry_count INT NOT NULL DEFAULT 0,
  next_retry_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_outbox_status_retry ON outbox_event(status, next_retry_at);
```

---

## 3. API ↔ DB 매핑 요약
| API                             | 주요 테이블                                                                                        | 읽기/쓰기 |
|---------------------------------|-----------------------------------------------------------------------------------------------|---|
| GET `/wallets/{userId}`         | `wallets`                                                                                     | R |
| POST `/wallets/{userId}/charge` | `wallets`                                                                                     | U |
| GET `/products`                 | `products`                                                                                    | R |
| GET `/products/{id}`            | `products`                                                                                    | R |
| POST `/coupons/claim`           | `coupons`                                                                                     | U, R |
| GET `/coupons?userId=`          | `coupons`                                                                                     | R |
| POST `/orders`                  | `products`(U), `wallets`(U), `orders`(C), `order_items`(C), `coupons`(U), `outbox_event`(C) | C/U |
| GET `/stats/top-products`       | `orders` + `order_items` + `products`                                                         | R |

---

## 4. 처리기준
- **orders.status**: `RESERVED`(주문완료), `PAID`(결제완료), `FAILED`(결제 실패/롤백), `CANCELED`(주문 취소)
- **coupons**: `claimed_by IS NULL` → 미발급, `claimed_by NOT NULL AND used_at IS NULL` → 보유, `used_at NOT NULL` → 사용
- **잔액/재고 차감**: 조건부 UPDATE 0행이면 실패 처리
- **Idempotency-Key**: `orders.idempotency_key` UNIQUE로 중복 생성 방지

