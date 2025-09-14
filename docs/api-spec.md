# Ecommerce Server 설계 - API Spec (v1)

> 문서 목적: 서버 구현 전 **요구 명세 합의용**. 엔티티 클래스 구현 전 단계에서 API 계약(요청/응답/에러/인증/헤더/제약)을 명확히 함.

## 0. 개요
- **Base URL (로컬)**: `http://localhost:8080/api`
- **Media Type**: `application/json; charset=utf-8`
- **멱등성**: 주문 생성 시 `Idempotency-Key` 헤더 필수
- **버전 정책**: URL 버전 포함(`/api/v1`)

---

## 1. 인증/보안/헤더

### 1.1 인증 
- **Authorization**: `Bearer <JWT>` JWT 토큰으로 사용자 인증 관리(Redis 활용)

### 1.2 멱등성 헤더
- **Idempotency-Key**: 주문/결제 API에서 **필수**. 클라이언트가 고유 UUID 생성하는 것으로 가정.
  - 동일 키로 같은 요청이 재시도되면 서버는 **첫 결과**를 반환해야함.

### 1.3 Request 헤더
| Header | Type | Required | Description |
|---|---|:---:|---|
| Authorization | string | optional | `Bearer <JWT>` |
| Content-Type | string | required | `application/json` |
| Idempotency-Key | string | required* | *`POST /orders`에서만 필수 |

### 1.4 Response 헤더
| Header | Description |
|---|---|
| X-Request-Id | 서버가 생성한 요청 추적 ID |
- 요청별 고유 ID
- 로깅 및 클라이언트 측에서 서버 측으로 특정 API 호출 문의 시 사용 목적
---

## 2. 에러 

### 2.1 에러 Response
```json
{
  "code": "INSUFFICIENT_BALANCE",
  "message": "잔액이 부족합니다.",
  "data": { "shortage": 1200 }
}
```

- `code`: 에러코드
- `message`: 사용자/로그용 간단 설명(option - 다국어처리)
- `data`: 선택, 상황별 부가 정보

### 2.2 공통 에러 코드 표
| HTTP | code | 설명 |
|:---:|---|---|
| 400 | INVALID_REQUEST | 스키마 위반/누락/범위 오류 |
| 401 | UNAUTHORIZED | Authorization 헤더 누락/토큰 불량 |
| 403 | FORBIDDEN | 권한 부족 |
| 404 | NOT_FOUND | 리소스 없음 |
| 409 | CONFLICT | 경합/상태 충돌(재고 부족, 중복 발급) |
| 422 | UNPROCESSABLE | 쿠폰 만료/타인 소유/이미 사용 |
| 429 | RATE_LIMITED | 요청 한도 초과 |
| 500 | INTERNAL_ERROR | 서버 내부 오류 |
| 502 | UPSTREAM_ERROR | 외부 전송 실패 등 |
| 402 | INSUFFICIENT_BALANCE | 잔액 부족 전용 코드 — 바디 code로 구분 |

---

## 3. API 상세

### 3.1 잔액 조회 — **GET** `/wallets/{userId}`
- 사용자의 현재 충전 잔액을 조회.

**Path Params**
- `userId` (long, required)

**Response 200**
```json
{ "userId": 101, "balance": 125000 }
```

**Errors**: `404 NOT_FOUND`(잔액/사용자 없음)

---

### 3.2 잔액 충전 — **POST** `/wallets/{userId}/charge`
- 충전 금액만큼 지갑 잔액을 증가.

**Path Params**
- `userId` (long, required)

**Request Body**
```json
{ "amount": 50000 }
```
- `amount` ≥ 1

**Response 200**
```json
{ "userId": 101, "balance": 175000 }
```

**Errors**
- `400 INVALID_REQUEST` (amount 음수/0)
- `404 NOT_FOUND` (사용자/잔액 없음)

---

### 3.3 상품 목록(상품 다건) — **GET** `/products`
- 판매 중 상품의 정보 제공.

**Query**
- `name` (string, optional) 상품명 검색 LIKE
- `sort` (string, name.desc, price.desc...) 정렬 ORDER BY
- `limit`(int) 최대 LIMIT

**Response 200**
```json
{
  "items": [
    { "id": 1, "name": "상품A", "price": 9900, "stock": 120 },
    { "id": 2, "name": "상품B", "price": 1100, "stock": 20 }
  ],
  "count": 2
}
```

---

### 3.4 상품 단건 — **GET** `/products/{id}`
**Response 200**
```json
{ "id": 2, "name": "상품C", "price": 34900, "stock": 42 }
```
**Errors**: `404 NOT_FOUND`

---

### 3.5 선착순 쿠폰 발급 — **POST** `/coupons/claim`
- 선착순 10인 10퍼센트 할인 쿠폰 지급 이벤트 시(=쿠폰 배치)
- 쿠폰 10개 데이터를 coupon 테이블에 사전 마이그레이션
- 특정 쿠폰 배치에서 두 사용자가 동시 발급 시도. => 동시발급 문제는 db의 row 단위 락으로 방지
- 한 사용자가 연속 클릭으로 2매 이상 발급 시도 => 멱등성 키로 체크.

**Request Body**
```json
{ "batchId": 10, "userId": 101 }
```

**Response 200**
```json
{
  "couponId": 555,
  "code": "SAVE10-AC5K",
  "batchId": 10,
  "claimedBy": 101,
  "claimedAt": "2025-08-31T10:00:10Z",
  "expiresAt": "2025-09-30T00:00:00Z"
}
```

**Errors**
- `409 CONFLICT` `SOLD_OUT` (남은 쿠폰 없음)
- `409 CONFLICT` `ALREADY_CLAIMED` (해당 배치 1인 1매 정책 위반)
- `422 UNPROCESSABLE` `BATCH_EXPIRED`

---

### 3.6 보유 쿠폰 목록 — **GET** `/coupons?userId={userId}`
**Response 200**
```json
{
  "items": [
    {
      "couponId": 555,
      "code": "SAVE10-AC5K",
      "batchId": 10,
      "status": "CLAIMED",
      "claimedAt": "2025-08-31T10:00:10Z",
      "expiresAt": "2025-09-30T00:00:00Z"
    }
  ]
}
```

---

### 3.7 주문/결제 — **POST** `/orders`
- **트랜잭션**: 재고 차감 → 잔액 차감 → 주문/아이템 생성 → 쿠폰 사용 처리
- **헤더**: `Idempotency-Key` **필수**

**Request Headers**
```
Idempotency-Key: 6e5b6a1a-27a3-4b2a-8f8a-2b7f8b3b1df9
```

**Request Body**
```json
{
  "userId": 101,
  "items": [
    { "productId": 1, "quantity": 2 },
    { "productId": 2, "quantity": 1 }
  ],
  "couponCode": "SAVE10-AC5K"
}
```

**Response 201**
```json
{
  "orderId": 9870,
  "status": "PAID",
  "totalPrice": 54700,
  "discountApplied": 5470,
  "finalPrice": 49230,
  "paidAt": "2025-08-31T10:02:00Z",
  "items": [
    { "productId": 1, "name": "USB-C Cable", "unitPrice": 9900, "quantity": 2 },
    { "productId": 2, "name": "GaN Charger 65W", "unitPrice": 34900, "quantity": 1 }
  ]
}
```

**Errors**
- `400 INVALID_REQUEST` (items 비었음/수량 ≤ 0)
- `404 NOT_FOUND` (상품/쿠폰 없음)
- `409 CONFLICT` `OUT_OF_STOCK` (재고 부족)
- `422 UNPROCESSABLE` `COUPON_INVALID | COUPON_EXPIRED | COUPON_USED | COUPON_OWNERSHIP_MISMATCH`
- `402 INSUFFICIENT_BALANCE`
- `409 CONFLICT` `ALREADY_PROCESSED` (같은 Idempotency-Key 재시도 시 기존 주문 반환)

---

### 3.8 상위 상품(최근 3일 Top-K) — **GET** `/stats/top-products`
**Query**
- `days` (int, default=3, min=1 max=30)
- `limit` (int, default=5, min=1 max=50)

**Response 200**
```json
{
  "range": { "from": "2025-08-28T00:00:00Z", "to": "2025-08-31T00:00:00Z" },
  "items": [
    { "productId": 2, "name": "GaN Charger 65W", "price": 34900, "sold": 120 },
    { "productId": 1, "name": "USB-C Cable", "price": 9900, "sold": 98 }
  ]
}
```
