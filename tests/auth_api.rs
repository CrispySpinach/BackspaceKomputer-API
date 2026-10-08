use sqlx::PgPool;

#[tokio::test]
#[ignore = "requires disposable TEST_DATABASE_URL"]
async fn registration_and_identity() {
    let pool = PgPool::connect(&std::env::var("TEST_DATABASE_URL").unwrap())
        .await
        .unwrap();
    sqlx::migrate!().run(&pool).await.unwrap();
    let user: serde_json::Value = sqlx::query_scalar("SELECT fn_register_customer($1)")
        .bind(serde_json::json!({"username":"registration_test","password":"long-test-password","nama_lengkap":"Test User","email":"registration@example.test"}))
        .fetch_one(&pool).await.unwrap();
    assert!(user["id"].is_number());
    assert!(user.get("password").is_none());
    let identity: serde_json::Value = sqlx::query_scalar(
        "SELECT fn_authenticate('customer', 'registration_test', 'long-test-password')",
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(identity["id"], user["id"]);
    assert_eq!(identity["role"], "customer");
}
