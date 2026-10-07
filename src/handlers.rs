// src/handlers.rs
use crate::{AppState, models::*};
use axum::{Json, extract::State, http::StatusCode, response::IntoResponse};

fn database_error(error: sqlx::Error) -> axum::response::Response {
    let code = error.as_database_error().and_then(|e| e.code());
    let (status, message) = match code.as_deref() {
        Some("22023" | "22P02" | "23514" | "23503") => (
            StatusCode::BAD_REQUEST,
            "Invalid request or insufficient stock",
        ),
        Some("42501") => (
            StatusCode::FORBIDDEN,
            "Employee is not allowed to perform this operation",
        ),
        Some("23505" | "40001" | "40P01") => (
            StatusCode::CONFLICT,
            "Operation conflicts with current data; retry the request",
        ),
        _ => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
    };
    // Do not expose SQL, parameters, or database internals in the response.
    (status, Json(serde_json::json!({"error": message}))).into_response()
}

pub async fn login_admin(
    State(state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> impl IntoResponse {
    let result = sqlx::query_scalar::<_, bool>("SELECT fn_login_admin($1, $2)")
        .bind(&payload.username)
        .bind(&payload.password)
        .fetch_one(&state.pool)
        .await;

    match result {
        Ok(true) => (
            StatusCode::OK,
            Json(serde_json::json!({
                "message": "Login successful"
            })),
        )
            .into_response(),
        Ok(false) => (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({
                "error": "Invalid username or password"
            })),
        )
            .into_response(),
        Err(e) => database_error(e),
    }
}

pub async fn get_produk(State(state): State<AppState>) -> impl IntoResponse {
    // ONLY calls the function that returns SETOF produk.
    let result = sqlx::query_as::<_, Produk>("SELECT * FROM fn_get_produk_aktif()")
        .fetch_all(&state.pool)
        .await;

    match result {
        Ok(produks) => (StatusCode::OK, Json(produks)).into_response(),
        Err(e) => database_error(e),
    }
}

pub async fn checkout(
    State(state): State<AppState>,
    Json(payload): Json<CheckoutRequest>,
) -> impl IntoResponse {
    let items_json = match serde_json::to_value(&payload.items) {
        Ok(json) => json,
        Err(_) => return (StatusCode::BAD_REQUEST, "Invalid items format").into_response(),
    };

    let result = sqlx::query("CALL sp_process_checkout($1, $2, $3)")
        .bind(payload.id_customer)
        .bind(payload.id_admin)
        .bind(items_json)
        .execute(&state.pool)
        .await;

    match result {
        Ok(_) => (
            StatusCode::CREATED,
            Json(serde_json::json!({
                "message": "Checkout successful. Transaction committed by database."
            })),
        )
            .into_response(),
        Err(e) => database_error(e),
    }
}

pub async fn get_laporan_penjualan(State(state): State<AppState>) -> impl IntoResponse {
    let result = sqlx::query_as::<_, LaporanPenjualan>("SELECT * FROM fn_get_laporan_penjualan()")
        .fetch_all(&state.pool)
        .await;

    match result {
        Ok(rows) => (StatusCode::OK, Json(rows)).into_response(),
        Err(e) => database_error(e),
    }
}
