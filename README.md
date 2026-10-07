# Backspace Komputer API
A Final Assignment Project for Database Management, A Computer Store API


## API Reference

#### Get all items

```http
  GET /api/items
```

| Parameter | Type     | Description                |
| :-------- | :------- | :------------------------- |
| `api_key` | `string` | **Required**. Your API key |

#### Get item

```http
  GET /api/items/${id}
```

| Parameter | Type     | Description                       |
| :-------- | :------- | :-------------------------------- |
| `id`      | `string` | **Required**. Id of item to fetch |


## Architecture and running locally

Rust/Axum handles HTTP and calls PostgreSQL functions or procedures through SQLx.
Handlers do not query or mutate tables directly. Start PostgreSQL with
`docker compose up -d --wait`, configure `DATABASE_URL` in your local environment,
then run `cargo run`. The API listens on `127.0.0.1:8080` and applies SQLx migrations.

Routes: `POST /api/admin/login`, `GET /api/produk`, `POST /api/checkout`,
`GET /api/reports/sales`. Checkout accepts `id_customer`, `id_admin`, and an `items`
array of `{ "id_produk": 1, "jumlah": 2 }`. A nonempty cart and an active
admin/cashier employee are required; a null employee no longer silently becomes
employee 1. Restocking requires an active admin/storage employee.

### Transaction behavior

A single `CALL` runs atomically in PostgreSQL's implicit transaction; any error
rolls back the order, details, and stock movements. The procedures intentionally
have no internal `COMMIT`/`ROLLBACK`, so they also work inside caller transactions.
Checkout locks product rows in ID order; stock-movement triggers also lock the
product row to prevent lost stock updates.

Corrections are forward migrations (`007`–`009`), leaving existing migration
checksums unchanged by this improvement pass. Do not edit previously applied
migrations or reset your database to bypass checksum errors. The earlier working
copy already renamed migration `005_create_index.sql`; an existing database may
need migration-history reconciliation before startup.

### Tests

- `cargo fmt --check`
- `cargo clippy --locked --all-targets --all-features -- -D warnings`
- `cargo test --locked` (database test is explicitly ignored by default)
- Set `TEST_DATABASE_URL` to a **disposable PostgreSQL 16 database**, then run
  `cargo test --locked -- --include-ignored` for SQLx migrations, model contracts,
  checkout totals, rollback, restocking restrictions, and concurrent last-item sales.

Never point the regression test at development or production data: existing seed
migration `005` truncates tables, and the tests deliberately change stock.
CI runs these tests against an isolated PostgreSQL service. Compose currently
contains PostgreSQL only, so its smoke check checks the database, not an API on port 3000.

### Security limitations / remaining work

This is a local assignment prototype, **not ready for public deployment**:
- Login verifies credentials but does not issue a session/token. Checkout trusts
  the supplied employee ID; database role checks do not prove caller identity.
  Add authenticated identity and bind employee IDs to it before exposing writes.
- Sales reports are currently public; add authorization alongside sessions.
- Docker configuration uses development credentials; replace these and restrict
  database networking before deployment.
- Passwords are hashed using pgcrypto, not reversibly encrypted. Do not log
  credential-bearing structs. JSON serialization excludes employee/customer passwords.
- Order-detail update/delete total maintenance, cancellation, signed stock
  adjustments, and full inventory-management endpoints remain future work.




## To-Do and Implementation Status
### SQL Implementation
- [x] Functions
- [x] Triggers
- [x] Stored Procedures
- [x] Views

### Indexing
- [x] B-Tree
- [ ] Hash
- [ ] Bitmap

### Transaction Processing
- [x] Transactions
- [x] Failure and Recovery
- [x] Concurrency and Control

### Extra Implementation
- [x] JSON