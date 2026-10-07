pub mod db;
pub mod handlers;
pub mod models;

#[derive(Clone)]
pub struct AppState {
    pub pool: sqlx::PgPool,
}
