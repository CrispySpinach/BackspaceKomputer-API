use backspacekomputer_api::{AppState, api, db};
use dotenvy::dotenv;
use std::net::SocketAddr;

#[tokio::main]
async fn main() {
    dotenv().ok();
    let secret =
        std::env::var("JWT_SECRET").expect("JWT_SECRET must be set (at least 32 random bytes)");
    assert!(
        secret.len() >= 32,
        "JWT_SECRET must contain at least 32 bytes"
    );
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

    let app = api::router(app_state, secret);

    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    println!("Server running on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
