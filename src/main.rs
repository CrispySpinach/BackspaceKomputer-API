use backspacekomputer_api::{AppState, db, handlers};

use axum::{
    Router,
    routing::{get, post},
};
use dotenvy::dotenv;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    dotenv().ok();
    println!("Connecting to database...");

    let pool = db::create_pool()
        .await
        .expect("Failed to create database pool");
    println!("Database connected.");

    println!("Running migrations...");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");
    println!("Migrations applied.");

    let app_state = AppState { pool: pool.clone() };

    let app = Router::new()
        .route("/api/admin/login", post(handlers::login_admin))
        .route("/api/produk", get(handlers::get_produk))
        .route("/api/checkout", post(handlers::checkout))
        .route("/api/reports/sales", get(handlers::get_laporan_penjualan))
        .with_state(app_state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    println!("Server running on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
