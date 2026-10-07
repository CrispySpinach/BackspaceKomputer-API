use backspacekomputer_api::{AppState, handlers, models};

#[test]
fn customer_password_is_never_serialized() {
    let customer = models::Customer {
        id: 1,
        username: "test".into(),
        email: "test@example.invalid".into(),
        password: "sensitive-hash".into(),
        nama_lengkap: "Test".into(),
    };
    let json = serde_json::to_value(customer).unwrap();
    assert!(json.get("password").is_none());
    assert_eq!(json["email"], "test@example.invalid");
}

#[tokio::test]
async fn database_outage_is_not_invalid_credentials() {
    use axum::{Json, extract::State, response::IntoResponse};
    let pool = sqlx::postgres::PgPoolOptions::new()
        .connect_lazy("postgres://localhost/unused")
        .unwrap();
    pool.close().await;
    let response = handlers::login_admin(
        State(AppState { pool }),
        Json(models::LoginRequest {
            username: "test".into(),
            password: "test".into(),
        }),
    )
    .await
    .into_response();
    assert_eq!(response.status(), 500);
    let body = axum::body::to_bytes(response.into_body(), 4096)
        .await
        .unwrap();
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&body).unwrap()["error"],
        "Internal server error"
    );
}

#[tokio::test]
#[ignore = "requires TEST_DATABASE_URL pointing to a disposable PostgreSQL database"]
async fn database_contract_and_checkout() {
    let url =
        std::env::var("TEST_DATABASE_URL").expect("explicit disposable test database required");
    let pool = sqlx::PgPool::connect(&url).await.unwrap();
    sqlx::migrate!("./migrations").run(&pool).await.unwrap();
    let products = sqlx::query_as::<_, models::Produk>("SELECT * FROM fn_get_produk_aktif()")
        .fetch_all(&pool)
        .await
        .expect("product model must match SQL columns");
    assert!(!products.is_empty());
    sqlx::query("CALL sp_process_checkout(1, 1, '[{\"id_produk\":1,\"jumlah\":2}]'::jsonb)")
        .execute(&pool)
        .await
        .expect("valid checkout commits atomically");
    let reports =
        sqlx::query_as::<_, models::LaporanPenjualan>("SELECT * FROM fn_get_laporan_penjualan()")
            .fetch_all(&pool)
            .await
            .expect("report model must match SQL columns");
    assert!(!reports.is_empty());
    let order = reports.iter().max_by_key(|r| r.pesanan_id).unwrap();
    assert_eq!(order.total_items, 1);
    assert_eq!(order.total_quantity, Some(2));
    assert_eq!(order.total_harga, rust_decimal::Decimal::from(3_000_000));
    assert_eq!(order.status.as_deref(), Some("selesai"));
    let movement: (i32, i32, i32) = sqlx::query_as(
        "SELECT jumlah, stok_sebelum, stok_sesudah FROM stok_movement WHERE id_pesanan = $1",
    )
    .bind(order.pesanan_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(movement.0, 2);
    assert_eq!(movement.1 - movement.2, 2);

    let before: (i64, i32) =
        sqlx::query_as("SELECT (SELECT count(*) FROM pesanan), stok FROM produk WHERE id = 1")
            .fetch_one(&pool)
            .await
            .unwrap();
    for (admin, items) in [
        (Some(1), serde_json::json!([])),
        (None, serde_json::json!([{"id_produk":1,"jumlah":1}])),
        (Some(1), serde_json::json!([{"id_produk":1,"jumlah":0}])),
        (Some(1), serde_json::json!([{"id_produk":1,"jumlah":-1}])),
        (
            Some(1),
            serde_json::json!([{"id_produk":1,"jumlah":1},{"id_produk":29,"jumlah":1}]),
        ),
        (Some(1), serde_json::json!([{"id_produk":31,"jumlah":1}])),
    ] {
        assert!(
            sqlx::query("CALL sp_process_checkout(1, $1, $2)")
                .bind(admin)
                .bind(items)
                .execute(&pool)
                .await
                .is_err(),
            "invalid checkout accepted"
        );
        let after: (i64, i32) =
            sqlx::query_as("SELECT (SELECT count(*) FROM pesanan), stok FROM produk WHERE id = 1")
                .fetch_one(&pool)
                .await
                .unwrap();
        assert_eq!(
            before, after,
            "failed checkout must roll back header and stock"
        );
    }
    assert!(
        sqlx::query("CALL sp_restock_product(1, 2, 1, 'cashier forbidden')")
            .execute(&pool)
            .await
            .is_err()
    );
    assert!(
        sqlx::query("CALL sp_restock_product(1, 1, -1, 'negative forbidden')")
            .execute(&pool)
            .await
            .is_err()
    );
    sqlx::query("CALL sp_restock_product(1, 1, 1, 'valid restock')")
        .execute(&pool)
        .await
        .unwrap();

    // Fixture setup is direct SQL only in tests, never in application handlers.
    sqlx::query("UPDATE produk SET stok = 1 WHERE id = 30")
        .execute(&pool)
        .await
        .unwrap();
    let first = sqlx::query("CALL sp_process_checkout(1, 1, '[{\"id_produk\":30,\"jumlah\":1}]')")
        .execute(&pool);
    let second = sqlx::query("CALL sp_process_checkout(1, 2, '[{\"id_produk\":30,\"jumlah\":1}]')")
        .execute(&pool);
    let (first, second) = tokio::join!(first, second);
    assert_ne!(
        first.is_ok(),
        second.is_ok(),
        "only one concurrent checkout may buy the last item"
    );
    let stock: i32 = sqlx::query_scalar("SELECT stok FROM produk WHERE id = 30")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(stock, 0);
}
