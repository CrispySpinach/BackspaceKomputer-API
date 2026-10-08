# Backspace Komputer API

Rust/Axum + SQLx + PostgreSQL computer-store API for a Database Management assignment.
All application database access invokes PostgreSQL functions/procedures. SQL joins,
mutations, validation, stock locking, and transactions live in migrations.

## Run locally

1. Start the database: `docker compose up -d --wait`.
2. Configure `DATABASE_URL` in your local `.env` (see `.env.example`).
3. Generate a signing key with `openssl rand -hex 32` and set it as `JWT_SECRET`
   in `.env` or your shell environment. Keep it private; do not commit it.
4. Run `cargo run --locked`. API address: `http://127.0.0.1:8080`.

Startup requires a JWT secret of at least 32 bytes. Use a randomly generated key,
not a memorable phrase. SQLx applies pending migrations automatically. Do not edit
applied migrations or manually change stored checksums. New features use migrations
011–014; existing migration files are unchanged in this feature update.

## Authentication

Customer registration: `POST /api/auth/register`:

```json
{"username":"andi_new","password":"a-long-unique-password","nama_lengkap":"Andi Pratama","email":"andi_new@example.com"}
```

Returns `201` and the created customer, without its password. Public registration
never creates employees or grants roles. Passwords must contain 8–72 bytes (bcrypt limit).

Customer login: `POST /api/auth/login`. Employee login: `POST /api/admin/login`.
Both accept:

```json
{"username":"andi_new","password":"a-long-unique-password"}
```

Successful login returns `access_token`, `token_type: "Bearer"`, `expires_in: 3600`,
and an identity object. In Postman select **Authorization → Bearer Token** and paste
`access_token`. Protected requests require `Authorization: Bearer <access_token>`.
JWTs use HS256 and validate signature, expiry, issuer, and audience. Employee/customer
IDs have distinct identity types. Active account status and current role are checked
in PostgreSQL on every protected request; deactivation blocks existing tokens.

## Endpoint reference

`{id}` denotes a numeric path parameter; it is not literal text in the URL.

| Method | Path | Access / behavior |
|---|---|---|
| POST | `/api/auth/register` | Public customer registration |
| POST | `/api/auth/login` | Public customer login, returns JWT |
| POST | `/api/admin/login` | Public employee login, returns JWT |
| GET | `/Profile` | Own customer or employee profile |
| PATCH / PUT | `/Profile` | Customer updates own username, name, email |
| GET / PATCH / PUT | `/api/auth/profile` | Same behavior as `/Profile` |
| GET | `/api/users` | Full admin: active customers |
| GET | `/api/users/{id}` | Full admin: customer by ID |
| DELETE | `/api/users/{id}` | Full admin: deactivate customer |
| DELETE | `/api/users` | Full admin: deactivate customer specified by JSON `{"id":123}` |
| GET | `/api/produk` | Public active product list |
| GET | `/api/produk/{id}` | Public active product details |
| POST | `/api/produk` | Admin/storage: create product and initial stock ledger |
| POST | `/api/produk/{id}/stock` | Admin/storage: add stock |
| DELETE | `/api/produk/{id}` | Admin/storage: discontinue, remove remaining stock, soft-delete |
| POST | `/api/orders` | Customer: own order; admin/cashier: order for a customer |
| GET | `/api/orders` | Customer: own orders; admin/cashier: all orders |
| GET | `/api/orders/{id}` | Authorized order header and `items` details |
| DELETE | `/api/orders/{id}` | Owner or admin/cashier: cancel and restore stock |
| POST | `/api/checkout` | Protected alias of POST `/api/orders` |
| GET | `/api/reports/sales` | Full admin only |

User/order lists accept `?limit=50&offset=0`; maximum page size is 100. Routes are
case-sensitive and shown without trailing slashes. `/Profile` has a capital P.

### Update profile

```json
{"nama_lengkap":"Updated Name","email":"updated@example.com"}
```

Only `username`, `nama_lengkap`, and `email` can be changed. Password/role/ID changes
are not accepted here. PUT and PATCH both merge the provided detail fields.

### Create product

```json
{"id_kategori":1,"nama_produk":"Mechanical Keyboard","harga":"950000.00","stok":10,"deskripsi":"Hot-swappable keyboard"}
```

Prices are validated and stored as PostgreSQL NUMERIC, never calculated using floats
in Rust. Initial stock is recorded as a movement. Creator identity comes from JWT.

### Add stock

```json
{"jumlah":5,"catatan":"Supplier delivery"}
```

### Place order

Customer body (customer identity comes from JWT):

```json
{"items":[{"id_produk":1,"jumlah":2}]}
```

Employee body:

```json
{"id_customer":1,"items":[{"id_produk":1,"jumlah":2}]}
```

**Breaking change:** Do not send `id_admin`. Employee identity is derived from JWT;
unknown top-level order fields are rejected. A customer cannot order as another
customer. The response is the created order including ID and item details.

### Cancellation and deletion semantics

- Checkout immediately creates a `selesai` order, matching the original assignment flow.
- Cancellation changes it to `dibatalkan` and restores stock with a ledger entry.
  There is no payment/refund integration. A second cancellation returns `409` and
  does not restore stock twice. Concurrent cancellations lock the order row.
- Product deletion is soft deletion and records removal of remaining stock.
- Cancellation can return stock to a discontinued product; it remains hidden and
  cannot be purchased. Historical order details are preserved.
- Customer deletion deactivates the account; it does not erase historical records.
- Missing or another customer's order returns `404`. Unauthorized roles return `403`.

## API request and response guide

### Conventions

- Base URL: `http://127.0.0.1:8080`.
- Send JSON bodies with `Content-Type: application/json`.
- For protected routes, set the `Authorization` header to `Bearer` followed by a
  space and the `access_token` returned by login. Never send `JWT_SECRET` to clients.
- Responses are direct objects or arrays, not wrapped in a `data` property.
- Examples below are illustrative, not captured responses. IDs, timestamps, stock,
  and totals depend on your database.
- GET and path-based DELETE requests do not need a body. Only `DELETE /api/users`
  requires the JSON body containing the target ID.

### Registration fields

| Field | Required | Rules |
|---|---|---|
| `username` | Yes | 3–50 characters after trimming; unique |
| `password` | Yes | 8–72 bytes; stored as a hash and never returned |
| `nama_lengkap` | Yes | 1–100 characters after trimming |
| `email` | Yes | Validated email format, maximum 100 characters; unique |

Successful registration returns `201 Created`:

```json
{
  "id": 4,
  "username": "andi_new",
  "nama_lengkap": "Andi Pratama",
  "email": "andi_new@example.com",
  "is_active": true
}
```

Registration does not return a JWT; call the customer login endpoint afterward.
Duplicate usernames or emails return `409 Conflict`.

### Login response

Both login endpoints return `200 OK` with this structure:

```json
{
  "access_token": "<signed-jwt-from-login>",
  "token_type": "Bearer",
  "expires_in": 3600,
  "user": {"id": 4, "kind": "customer", "role": "customer"}
}
```

Employee identities use `kind: "employee"` and a role of `admin`, `cashier`, or
`storage`. A customer ID and employee ID can have the same number; `kind`
distinguishes them. Invalid credentials return `401`.

### Profiles and users

`GET /Profile` and successful profile updates return the customer object shown
in the registration example. Employee profiles instead contain `id`, `id_role`,
`username`, `nama`, `email`, and `is_active`; passwords are excluded.

- `GET /api/users` returns an array of active customer objects.
- `GET /api/users/{id}` returns one active customer object.
- User deletion returns `200 OK`, for example `{"id":4,"deleted":true}`.
- Deleted customers cannot log in or use existing tokens. Their usernames/emails
  remain reserved because their records are retained for order history.
- Profile updates do not issue a replacement token. Employee profile updates are
  not supported by the current customer-only update endpoint.

### Product fields and responses

| Create field | Required | Rules |
|---|---|---|
| `id_kategori` | Yes | Existing category ID |
| `nama_produk` | Yes | 1–150 characters after trimming |
| `harga` | Yes | Nonnegative decimal below 100000000, at most two decimal places; send as a decimal string |
| `stok` | No | Nonnegative integer, defaults to zero |
| `deskripsi` | No | Text description |

`POST /api/produk` returns `201`; product detail and restock return `200` with a
product object. Illustrative detail response:

```json
{
  "id": 32,
  "id_kategori": 1,
  "id_admin": 1,
  "nama_produk": "Mechanical Keyboard",
  "harga": 950000.00,
  "stok": 10,
  "deskripsi": "Hot-swappable keyboard",
  "status": "active",
  "deleted_at": null
}
```

The existing `GET /api/produk` list uses Rust Decimal serialization and returns
`harga` as a string; JSONB-based detail/create/restock endpoints return a JSON
number. Clients should handle this current representation difference.

Restock requires a positive integer `jumlah`; `catatan` is optional and limited
to 255 characters. It returns the product with the updated stock.
Product deletion returns `200`, for example `{"id":32,"deleted":true}`.
Deleted/discontinued products are not available through the public detail route.
The product list currently has no pagination or search parameters.

### Order fields and responses

| Field | Required | Rules |
|---|---|---|
| `id_customer` | Employees only | Active customer ID; customers should omit it |
| `items` | Yes | Array containing 1–100 entries |
| `items[].id_produk` | Yes | Active product ID |
| `items[].jumlah` | Yes | Positive integer; sufficient stock required |

Prices come from PostgreSQL, not the client. `id_admin` and other unknown top-level
order fields are rejected. The successful order-create response is `201`; detail
and cancellation responses are `200` with the same structure:

```json
{
  "id": 12,
  "id_customer": 4,
  "id_admin": null,
  "tanggal_pesanan": "2026-10-07T10:00:00",
  "total_harga": 950000.00,
  "status": "selesai",
  "items": [
    {
      "id": 15,
      "id_pesanan": 12,
      "id_produk": 32,
      "jumlah": 1,
      "harga_satuan": 950000.00,
      "harga_subtotal": 950000.00
    }
  ]
}
```

`id_admin` is null for customer self-checkout and identifies the authenticated
employee for staff checkout. Cancellation returns the order with status
`dibatalkan`; historical quantities and purchase prices remain unchanged.
`GET /api/orders` returns an array of order headers **without** nested `items`.
Use the detail endpoint to retrieve the items.

### Pagination

For users and orders:

```http
GET /api/users?limit=20&offset=0
GET /api/orders?limit=20&offset=20
```

Default `limit` is 50 and default `offset` is zero. SQL clamps the limit to 1–100
and negative offsets to zero. Responses are arrays with no total-count metadata.
Users are sorted by ascending ID; orders by descending ID.

### Sales report

`GET /api/reports/sales` returns `200` and an array with these fields:
`pesanan_id`, `customer_name`, `cashier_name`, `tanggal_pesanan`, `total_harga`,
`status`, `total_items`, and `total_quantity`.

`total_items` counts detail rows; `total_quantity` sums their quantities.
`cashier_name` can be null for customer checkout. Money is serialized as a string
on this existing Rust-model endpoint. The current report includes cancelled orders;
check `status` when interpreting sales. This endpoint is admin-only and unpaginated.

### Error responses

Application errors use an `error` property, for example:

```json
{"error":"Invalid request or insufficient stock"}
```

| Status | Meaning |
|---|---|
| `400 Bad Request` | Invalid business input, insufficient stock, or malformed request |
| `401 Unauthorized` | Missing/invalid/expired JWT, inactive account, or invalid login credentials |
| `403 Forbidden` | Actor lacks permission for the operation |
| `404 Not Found` | Resource absent, inactive/hidden, or order belongs to another customer |
| `409 Conflict` | Duplicate username/email, already-cancelled order, or database concurrency conflict |
| `415 Unsupported Media Type` | JSON endpoint called without the required JSON content type |
| `422 Unprocessable Entity` | JSON cannot be decoded into a typed request, such as an unknown checkout field |
| `500 Internal Server Error` | Unexpected database or server failure |

Axum extractor errors (invalid JSON, path/query types, or content type) may be
plain text rather than the application JSON error format. Do not assume every
non-success response can be parsed as JSON. Do not automatically retry order
creation after a network timeout: this API has no idempotency-key support.

### Postman quick workflow

1. Create a collection variable `base_url` with value `http://127.0.0.1:8080`.
2. Register with `POST {{base_url}}/api/auth/register`, using **Body → raw → JSON**.
3. Log in with `POST {{base_url}}/api/auth/login`.
4. Copy the response's `access_token` into a private Postman variable `token`.
5. On protected requests, select **Authorization → Bearer Token** and enter `{{token}}`.
6. Request `GET {{base_url}}/Profile`, then PATCH the same URL with changed details.
7. Browse products; place an order with `POST {{base_url}}/api/orders`.
8. Use its returned ID for `GET` and `DELETE {{base_url}}/api/orders/{id}`.
9. Use an employee token from `/api/admin/login` to test role-specific actions.

Use separate private token variables for customer, admin, cashier, and storage
accounts. Do not export live tokens or passwords in shared Postman collections.

## Tests

```bash
cargo fmt --check
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo test --locked
```

For all integration tests, use a **fresh disposable PostgreSQL 16 database**:

```bash
TEST_DATABASE_URL='postgres://.../disposable_test_database' cargo test --locked -- --include-ignored
```

Tests create fixed-name fixture users and modify orders/stock. Use a fresh database
for each full run. Never use a development/production database: migration 005 contains
TRUNCATE. CI provides an isolated PostgreSQL service. The new endpoint test exercises
the actual Axum router with HTTP requests, JWT middleware, and real PostgreSQL.

## Deployment limitations

This is an assignment API, not a complete production authentication service. Before
public deployment add TLS, login throttling, password reset/change, refresh/logout
revocation, secret rotation practices, and least-privilege database credentials.
The development Compose credentials must be replaced. Never log password-bearing
request structs or JWTs. There is no public employee-registration endpoint; provision
storage employees through a controlled database administration workflow.
