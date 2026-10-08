use axum::{
    body::{Body, to_bytes},
    http::Request,
};
use backspacekomputer_api::{AppState, api};
use serde_json::{Value, json};
use tower::ServiceExt;

async fn request(
    app: &axum::Router,
    method: &str,
    path: &str,
    token: &str,
    body: Value,
) -> (u16, Value) {
    let mut req = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if !token.is_empty() {
        req = req.header("authorization", format!("Bearer {token}"));
    }
    let response = app
        .clone()
        .oneshot(req.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = to_bytes(response.into_body(), 1_000_000).await.unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}
#[tokio::test]
#[ignore = "requires disposable TEST_DATABASE_URL"]
async fn authenticated_workflow() {
    let pool = sqlx::PgPool::connect(&std::env::var("TEST_DATABASE_URL").unwrap())
        .await
        .unwrap();
    sqlx::migrate!().run(&pool).await.unwrap();
    let app = api::router(
        AppState { pool: pool.clone() },
        "test-secret-with-at-least-thirty-two-bytes".into(),
    );
    assert_eq!(request(&app, "GET", "/Profile", "", json!({})).await.0, 401);
    let (s,u)=request(&app,"POST","/api/auth/register","",json!({"username":"http_test","password":"test-password-123","nama_lengkap":"HTTP Test","email":"http@test.example"})).await;
    assert_eq!(s, 201, "{u}");
    let uid = u["id"].as_i64().unwrap();
    let (s, login) = request(
        &app,
        "POST",
        "/api/auth/login",
        "",
        json!({"username":"http_test","password":"test-password-123"}),
    )
    .await;
    assert_eq!(s, 200, "{login}");
    let token = login["access_token"].as_str().unwrap();
    assert_eq!(
        request(&app, "GET", "/Profile", token, json!({})).await.1["id"],
        uid
    );
    assert_eq!(
        request(
            &app,
            "PATCH",
            "/Profile",
            token,
            json!({"nama_lengkap":"Updated"})
        )
        .await
        .1["nama_lengkap"],
        "Updated"
    );
    assert_eq!(
        request(&app, "GET", "/api/users", token, json!({})).await.0,
        403
    );
    let (_, admin) = request(
        &app,
        "POST",
        "/api/admin/login",
        "",
        json!({"username":"employee_budi","password":"employee123"}),
    )
    .await;
    let admin = admin["access_token"].as_str().unwrap();
    assert_eq!(
        request(&app, "GET", "/api/users", admin, json!({})).await.0,
        200
    );
    assert_eq!(
        request(&app, "GET", &format!("/api/users/{uid}"), admin, json!({}))
            .await
            .0,
        200
    );
    let(s,p)=request(&app,"POST","/api/produk",admin,json!({"id_kategori":1,"nama_produk":"Test Product","harga":"1000.00","stok":5,"deskripsi":"Test"})).await;
    assert_eq!(s, 201, "{p}");
    let pid = p["id"].as_i64().unwrap();
    assert_eq!(
        request(
            &app,
            "POST",
            &format!("/api/produk/{pid}/stock"),
            admin,
            json!({"jumlah":2,"catatan":"restock"})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(&app, "GET", &format!("/api/produk/{pid}"), "", json!({}))
            .await
            .1["stok"],
        7
    );
    let (s, order) = request(
        &app,
        "POST",
        "/api/orders",
        token,
        json!({"items":[{"id_produk":pid,"jumlah":2}]}),
    )
    .await;
    assert_eq!(s, 201, "{order}");
    let oid = order["id"].as_i64().unwrap();
    let (_, other_login) = request(
        &app,
        "POST",
        "/api/auth/login",
        "",
        json!({"username":"user_dewi","password":"user123"}),
    )
    .await;
    let other = other_login["access_token"].as_str().unwrap();
    assert_eq!(
        request(&app, "GET", &format!("/api/orders/{oid}"), other, json!({}))
            .await
            .0,
        404
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/orders/{oid}"),
            other,
            json!({})
        )
        .await
        .0,
        404
    );
    assert_eq!(
        request(
            &app,
            "POST",
            "/api/orders",
            other,
            json!({"id_customer":uid,"items":[{"id_produk":pid,"jumlah":1}]})
        )
        .await
        .0,
        403
    );
    assert_eq!(
        request(&app, "PATCH", "/Profile", token, json!({"role":"admin"}))
            .await
            .0,
        400
    );
    assert_eq!(
        request(
            &app,
            "POST",
            "/api/checkout",
            token,
            json!({"id_admin":1,"items":[]})
        )
        .await
        .0,
        422
    );
    let (_, cashier_login) = request(
        &app,
        "POST",
        "/api/admin/login",
        "",
        json!({"username":"employee_siti","password":"employee123"}),
    )
    .await;
    let cashier = cashier_login["access_token"].as_str().unwrap();
    assert_eq!(
        request(
            &app,
            "POST",
            &format!("/api/produk/{pid}/stock"),
            cashier,
            json!({"jumlah":1})
        )
        .await
        .0,
        403
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/produk/{pid}"),
            cashier,
            json!({})
        )
        .await
        .0,
        403
    );
    assert_eq!(
        request(&app, "GET", "/api/reports/sales", token, json!({}))
            .await
            .0,
        403
    );
    // Add an employee only in the disposable test DB; there is no public staff registration.
    sqlx::query("INSERT INTO admin(id_role,username,password,nama,email) SELECT id,'storage_test',fn_hash_password('storage-password'),'Storage','storage@test.example' FROM role WHERE nama_role='storage'")
        .execute(&pool).await.unwrap();
    let (_, storage_login) = request(
        &app,
        "POST",
        "/api/admin/login",
        "",
        json!({"username":"storage_test","password":"storage-password"}),
    )
    .await;
    let storage = storage_login["access_token"].as_str().unwrap();
    assert_eq!(
        request(
            &app,
            "POST",
            "/api/orders",
            storage,
            json!({"id_customer":uid,"items":[{"id_produk":pid,"jumlah":1}]})
        )
        .await
        .0,
        403
    );
    let (status, storage_product) = request(
        &app,
        "POST",
        "/api/produk",
        storage,
        json!({"id_kategori":1,"nama_produk":"Storage product","harga":"10.00","stok":1}),
    )
    .await;
    assert_eq!(status, 201);
    let spid = storage_product["id"].as_i64().unwrap();
    assert_eq!(
        request(
            &app,
            "POST",
            &format!("/api/produk/{spid}/stock"),
            storage,
            json!({"jumlah":1})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/produk/{spid}"),
            storage,
            json!({})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(&app, "GET", "/Profile", "invalid.jwt.token", json!({}))
            .await
            .0,
        401
    );
    let expired=jsonwebtoken::encode(&jsonwebtoken::Header::default(),&json!({"sub":uid.to_string(),"kind":"customer","exp":1,"iss":"backspacekomputer","aud":"backspacekomputer-api"}),&jsonwebtoken::EncodingKey::from_secret(b"test-secret-with-at-least-thirty-two-bytes")).unwrap();
    assert_eq!(
        request(&app, "GET", "/Profile", &expired, json!({}))
            .await
            .0,
        401
    );
    assert_eq!(
        request(&app, "GET", "/api/orders", token, json!({}))
            .await
            .0,
        200
    );
    assert_eq!(
        request(&app, "GET", &format!("/api/orders/{oid}"), token, json!({}))
            .await
            .1["items"][0]["jumlah"],
        2
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/orders/{oid}"),
            token,
            json!({})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/orders/{oid}"),
            token,
            json!({})
        )
        .await
        .0,
        409
    );
    assert_eq!(
        request(&app, "GET", &format!("/api/produk/{pid}"), "", json!({}))
            .await
            .1["stok"],
        7
    );
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/produk/{pid}"),
            admin,
            json!({})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(&app, "GET", &format!("/api/produk/{pid}"), "", json!({}))
            .await
            .0,
        404
    );
    // Two cancellations of the same fresh order must restore stock only once.
    let (status, fresh_product) = request(
        &app,
        "POST",
        "/api/produk",
        admin,
        json!({"id_kategori":1,"nama_produk":"Concurrency product","harga":"10.00","stok":7}),
    )
    .await;
    assert_eq!(status, 201);
    let pid = fresh_product["id"].as_i64().unwrap();
    let (status, concurrent_order) = request(
        &app,
        "POST",
        "/api/orders",
        token,
        json!({"items":[{"id_produk":pid,"jumlah":1}]}),
    )
    .await;
    assert_eq!(status, 201);
    let cancel_path = format!("/api/orders/{}", concurrent_order["id"]);
    let (c1, c2) = tokio::join!(
        request(&app, "DELETE", &cancel_path, token, json!({})),
        request(&app, "DELETE", &cancel_path, token, json!({}))
    );
    let mut statuses = [c1.0, c2.0];
    statuses.sort();
    assert_eq!(statuses, [200, 409]);
    assert_eq!(
        request(&app, "GET", &format!("/api/produk/{pid}"), "", json!({}))
            .await
            .1["stok"],
        7
    );
    let (status, employee_order) = request(
        &app,
        "POST",
        "/api/checkout",
        cashier,
        json!({"id_customer":uid,"items":[{"id_produk":pid,"jumlah":1}]}),
    )
    .await;
    assert_eq!(status, 201);
    assert_eq!(employee_order["id_admin"], 2);
    assert_eq!(
        request(
            &app,
            "DELETE",
            &format!("/api/orders/{}", employee_order["id"]),
            cashier,
            json!({})
        )
        .await
        .0,
        200
    );
    assert_eq!(
        request(&app, "GET", "/api/orders", admin, json!({}))
            .await
            .0,
        200
    );
    assert_eq!(
        request(&app, "GET", "/api/users?limit=1", admin, json!({}))
            .await
            .1
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(request(&app,"POST","/api/auth/register","",json!({"username":"http_test","password":"test-password-123","nama_lengkap":"Duplicate","email":"duplicate@test.example"})).await.0,409);
    assert_eq!(
        request(
            &app,
            "POST",
            "/api/auth/login",
            "",
            json!({"username":"http_test","password":"wrong-password"})
        )
        .await
        .0,
        401
    );
    assert_eq!(
        request(&app, "DELETE", "/api/users", admin, json!({"id":uid}))
            .await
            .0,
        200
    );
    assert_eq!(
        request(&app, "GET", "/Profile", token, json!({})).await.0,
        401
    );
}
