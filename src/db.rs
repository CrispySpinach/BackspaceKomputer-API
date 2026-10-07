use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;
use std::env;

pub async fn create_pool() -> Result<PgPool, sqlx::Error> {
    let database_url = env::var("DATABASE_URL").expect("DATABASE_URL must be set in env");

    PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
}
