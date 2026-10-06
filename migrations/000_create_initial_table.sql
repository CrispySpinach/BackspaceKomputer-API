CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE role (
    id SERIAL PRIMARY KEY,
    nama_role VARCHAR(50) NOT NULL,
    deskripsi VARCHAR(150)
);

CREATE TABLE admin (
    id SERIAL PRIMARY KEY,
    id_role INT NOT NULL REFERENCES role(id) ON DELETE RESTRICT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    nama VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE customer (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    nama_lengkap VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE kategori (
    id SERIAL PRIMARY KEY,
    nama_kategori VARCHAR(100) NOT NULL
);

CREATE TABLE produk (
    id SERIAL PRIMARY KEY,
    id_kategori INT NOT NULL REFERENCES kategori(id) ON DELETE RESTRICT,
    id_admin INT REFERENCES admin(id) ON DELETE SET NULL,
    nama_produk VARCHAR(150) NOT NULL,
    harga DECIMAL(10, 2) NOT NULL CHECK (harga >= 0),
    stok INT NOT NULL DEFAULT 0 CHECK (stok >= 0),
    deskripsi TEXT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'discontinued')),
    deleted_at TIMESTAMP
);

CREATE TABLE pesanan (
    id SERIAL PRIMARY KEY,
    id_customer INT NOT NULL REFERENCES customer(id) ON DELETE RESTRICT,
    id_admin INT REFERENCES admin(id) ON DELETE SET NULL,
    tanggal_pesanan TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_harga DECIMAL(12, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'selesai', 'dibatalkan'))
);

CREATE TABLE detail_pesanan (
    id SERIAL PRIMARY KEY,
    id_pesanan INT NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    id_produk INT NOT NULL REFERENCES produk(id) ON DELETE RESTRICT,
    jumlah INT NOT NULL CHECK (jumlah > 0),
    harga_satuan DECIMAL(10, 2) NOT NULL,
    harga_subtotal DECIMAL(12, 2) NOT NULL
);

CREATE TABLE stok_movement (
    id SERIAL PRIMARY KEY,
    id_produk INT NOT NULL REFERENCES produk(id) ON DELETE RESTRICT,
    id_admin INT NOT NULL REFERENCES admin(id) ON DELETE RESTRICT,
    id_pesanan INT REFERENCES pesanan(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    jenis VARCHAR(20) NOT NULL CHECK (jenis IN ('masuk', 'keluar', 'penjualan', 'penyesuaian', 'penghapusan')),
    jumlah INT NOT NULL,
    stok_sebelum INT NOT NULL,
    stok_sesudah INT NOT NULL,
    catatan VARCHAR(255)
);