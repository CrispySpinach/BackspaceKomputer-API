use chrono::NaiveDateTime;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Role {
    pub id: i32,
    pub nama_role: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Admin {
    pub id: i32,
    pub id_role: i32,
    pub username: String,

    #[serde(skip_serializing)]
    pub password: String,
    pub nama: String,
    pub email: String,
    pub is_active: bool,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Customer {
    pub id: i32,
    pub username: String,

    pub email: String,
    #[serde(skip_serializing)]
    pub password: String,
    pub nama_lengkap: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Category {
    pub id: i32,
    pub nama_kategori: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Produk {
    pub id: i32,
    pub id_kategori: i32,
    pub id_admin: Option<i32>,
    pub nama_produk: String,
    pub harga: Decimal,
    pub stok: i32,
    pub deskripsi: Option<String>,
    pub status: Option<String>,
    pub deleted_at: Option<NaiveDateTime>,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct Pesanan {
    pub id: i32,
    pub id_customer: i32,
    pub id_admin: Option<i32>,
    pub tanggal_pesanan: NaiveDateTime,
    pub total_harga: Decimal,
    pub status: String,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct DetailPesanan {
    pub id: i32,
    pub id_pesanan: i32,
    pub id_produk: i32,
    pub jumlah: i32,
    pub harga_satuan: Decimal,
    pub harga_subtotal: Decimal,
}

#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct CheckoutRequest {
    pub id_customer: i32,
    pub id_admin: Option<i32>,
    pub items: Vec<CheckoutItem>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CheckoutItem {
    pub id_produk: i32,
    pub jumlah: i32,
}

#[derive(Debug, Serialize, Deserialize, FromRow)]
pub struct LaporanPenjualan {
    pub pesanan_id: i32,
    pub customer_name: String,
    pub cashier_name: Option<String>,
    pub tanggal_pesanan: Option<NaiveDateTime>,
    pub total_harga: Decimal,
    pub status: Option<String>,
    pub total_items: i64,
    pub total_quantity: Option<i64>,
}
