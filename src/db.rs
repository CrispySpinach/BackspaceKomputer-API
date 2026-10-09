use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;
use std::env;

pub async fn create_pool() -> Result<PgPool, sqlx::Error> {
    let user = env::var("POSTGRES_USER").expect("POSTGRES_USER must be set");
    let password = env::var("POSTGRES_PASSWORD").expect("POSTGRES_PASSWORD must be set");
    let postdb = env::var("POSTGRES_DB").expect("POSTGRES_DB must be set");
    let dbport = env::var("POSTGRES_PORT").expect("POSTGRES_PORT must be set");
    let dbhost = env::var("POSTGRES_HOST").expect("POSTGRES_HOST must be set");

    let database_url = format!(
        "postgres://{}:{}@{}:{}/{}",
        user, password, dbhost, dbport, postdb
    );

    PgPoolOptions::new()
        .max_connections(10)
        .connect(&database_url)
        .await
}
