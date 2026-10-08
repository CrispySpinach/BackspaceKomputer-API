use crate::{
    AppState,
    handlers::{self, database_error},
    models::LoginRequest,
};
use axum::{
    Extension, Json, Router,
    extract::{Path, Query, Request, State},
    http::StatusCode,
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::sync::Arc;

#[derive(Clone)]
struct AuthState {
    app: AppState,
    secret: Arc<String>,
}
#[derive(Clone, Serialize, Deserialize)]
struct Claims {
    sub: String,
    kind: String,
    exp: usize,
    iss: String,
    aud: String,
}
#[derive(Clone, Deserialize)]
struct Actor {
    id: i32,
    kind: String,
    role: String,
}
fn error(status: StatusCode, msg: &str) -> Response {
    (status, Json(json!({"error":msg}))).into_response()
}
fn result(value: Result<Value, sqlx::Error>, status: StatusCode) -> Response {
    match value {
        Ok(v) => (status, Json(v)).into_response(),
        Err(e) => database_error(e),
    }
}

pub fn router(app: AppState, secret: String) -> Router {
    assert!(
        secret.len() >= 32,
        "JWT_SECRET must contain at least 32 bytes"
    );
    let auth = AuthState {
        app: app.clone(),
        secret: Arc::new(secret),
    };
    let protected = Router::new()
        .route(
            "/Profile",
            get(profile).patch(update_profile).put(update_profile),
        )
        .route(
            "/api/auth/profile",
            get(profile).patch(update_profile).put(update_profile),
        )
        .route("/api/users", get(users).delete(delete_user_body))
        .route("/api/users/{id}", get(user).delete(delete_user))
        .route("/api/produk", post(create_product))
        .route("/api/produk/{id}", axum::routing::delete(delete_product))
        .route("/api/produk/{id}/stock", post(add_stock))
        .route("/api/orders", get(orders).post(place_order))
        .route("/api/orders/{id}", get(order).delete(cancel_order))
        .route("/api/checkout", post(place_order))
        .route("/api/reports/sales", get(reports))
        .route_layer(middleware::from_fn_with_state(auth.clone(), authenticate));
    Router::new()
        .merge(protected)
        .route("/api/auth/register", post(register))
        .route("/api/auth/login", post(customer_login))
        .route("/api/admin/login", post(employee_login))
        .route("/api/produk", get(handlers::get_produk))
        .route("/api/produk/{id}", get(product))
        .layer(Extension(auth))
        .with_state(app)
}
async fn authenticate(State(auth): State<AuthState>, mut req: Request, next: Next) -> Response {
    let token = req
        .headers()
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "));
    let Some(token) = token else {
        return error(StatusCode::UNAUTHORIZED, "Bearer token required");
    };
    let mut validation = Validation::new(Algorithm::HS256);
    validation.set_issuer(&["backspacekomputer"]);
    validation.set_audience(&["backspacekomputer-api"]);
    validation.leeway = 0;
    let claims = match decode::<Claims>(
        token,
        &DecodingKey::from_secret(auth.secret.as_bytes()),
        &validation,
    ) {
        Ok(v) => v.claims,
        Err(_) => return error(StatusCode::UNAUTHORIZED, "Invalid or expired token"),
    };
    let Ok(id) = claims.sub.parse::<i32>() else {
        return error(StatusCode::UNAUTHORIZED, "Invalid token");
    };
    let actor = sqlx::query_scalar::<_, Option<Value>>("SELECT fn_actor($1,$2)")
        .bind(&claims.kind)
        .bind(id)
        .fetch_one(&auth.app.pool)
        .await;
    match actor {
        Ok(Some(v)) => match serde_json::from_value::<Actor>(v) {
            Ok(a) => {
                req.extensions_mut().insert(a);
                next.run(req).await
            }
            Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
        },
        Ok(None) => error(StatusCode::UNAUTHORIZED, "Account inactive"),
        Err(e) => database_error(e),
    }
}
async fn login(auth: AuthState, p: LoginRequest, kind: &str) -> Response {
    let actor = sqlx::query_scalar::<_, Option<Value>>("SELECT fn_authenticate($1,$2,$3)")
        .bind(kind)
        .bind(p.username)
        .bind(p.password)
        .fetch_one(&auth.app.pool)
        .await;
    let actor = match actor {
        Ok(Some(v)) => v,
        Ok(None) => return error(StatusCode::UNAUTHORIZED, "Invalid username or password"),
        Err(e) => return database_error(e),
    };
    let claims = Claims {
        sub: actor["id"].to_string(),
        kind: kind.into(),
        exp: (chrono::Utc::now().timestamp() + 3600) as usize,
        iss: "backspacekomputer".into(),
        aud: "backspacekomputer-api".into(),
    };
    match encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(auth.secret.as_bytes()),
    ) {
        Ok(token) => {
            Json(json!({"access_token":token,"token_type":"Bearer","expires_in":3600,"user":actor}))
                .into_response()
        }
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
    }
}
async fn customer_login(
    Extension(auth): Extension<AuthState>,
    Json(p): Json<LoginRequest>,
) -> Response {
    login(auth, p, "customer").await
}
async fn employee_login(
    Extension(auth): Extension<AuthState>,
    Json(p): Json<LoginRequest>,
) -> Response {
    login(auth, p, "employee").await
}
async fn register(State(s): State<AppState>, Json(p): Json<Value>) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_register_customer($1)")
            .bind(p)
            .fetch_one(&s.pool)
            .await,
        StatusCode::CREATED,
    )
}
async fn profile(State(s): State<AppState>, Extension(a): Extension<Actor>) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_profile($1,$2)")
            .bind(a.kind)
            .bind(a.id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn update_profile(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Json(p): Json<Value>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_update_profile($1,$2,$3)")
            .bind(a.kind)
            .bind(a.id)
            .bind(p)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
#[derive(Deserialize)]
struct Page {
    #[serde(default = "default_limit")]
    limit: i32,
    #[serde(default)]
    offset: i32,
}
fn default_limit() -> i32 {
    50
}
async fn users(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Query(p): Query<Page>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_users($1,$2,NULL,$3,$4)")
            .bind(a.kind)
            .bind(a.id)
            .bind(p.limit)
            .bind(p.offset)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn user(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_users($1,$2,$3,1,0)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn delete_user(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_delete_user($1,$2,$3)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Target {
    id: i32,
}
async fn delete_user_body(
    s: State<AppState>,
    a: Extension<Actor>,
    Json(p): Json<Target>,
) -> Response {
    delete_user(s, a, Path(p.id)).await
}
async fn product(State(s): State<AppState>, Path(id): Path<i32>) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_product($1)")
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn create_product(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Json(p): Json<Value>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_create_product($1,$2,$3)")
            .bind(a.kind)
            .bind(a.id)
            .bind(p)
            .fetch_one(&s.pool)
            .await,
        StatusCode::CREATED,
    )
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Stock {
    jumlah: i32,
    catatan: Option<String>,
}
async fn add_stock(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
    Json(p): Json<Stock>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_add_stock($1,$2,$3,$4,$5)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .bind(p.jumlah)
            .bind(p.catatan)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn delete_product(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_delete_product($1,$2,$3)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn orders(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Query(p): Query<Page>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_orders($1,$2,NULL,$3,$4)")
            .bind(a.kind)
            .bind(a.id)
            .bind(p.limit)
            .bind(p.offset)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn order(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_orders($1,$2,$3,1,0)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Order {
    id_customer: Option<i32>,
    items: Vec<crate::models::CheckoutItem>,
}
async fn place_order(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Json(p): Json<Order>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_place_order($1,$2,$3,$4)")
            .bind(a.kind)
            .bind(a.id)
            .bind(p.id_customer)
            .bind(json!(p.items))
            .fetch_one(&s.pool)
            .await,
        StatusCode::CREATED,
    )
}
async fn cancel_order(
    State(s): State<AppState>,
    Extension(a): Extension<Actor>,
    Path(id): Path<i32>,
) -> Response {
    result(
        sqlx::query_scalar("SELECT fn_cancel_order($1,$2,$3)")
            .bind(a.kind)
            .bind(a.id)
            .bind(id)
            .fetch_one(&s.pool)
            .await,
        StatusCode::OK,
    )
}
async fn reports(s: State<AppState>, Extension(a): Extension<Actor>) -> Response {
    if a.role != "admin" {
        return error(StatusCode::FORBIDDEN, "Admin required");
    }
    handlers::get_laporan_penjualan(s).await.into_response()
}
