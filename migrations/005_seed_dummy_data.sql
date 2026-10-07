-- migrations/20261007000009_seed_testing_data.sql

-- =====================================================
-- WARNING:
-- This seed truncates existing data for deterministic testing.
-- If you do not want to delete existing data, remove the TRUNCATE line.
-- =====================================================

TRUNCATE TABLE
    stok_movement,
    detail_pesanan,
    pesanan,
    produk,
    kategori,
    customer,
    admin,
    role
RESTART IDENTITY CASCADE;

INSERT INTO role (id, nama_role, deskripsi) VALUES
(1, 'admin', 'Full system access'),
(2, 'cashier', 'Processes sales and checkout'),
(3, 'storage', 'Manages stock and inventory');

INSERT INTO admin (
    id,
    id_role,
    username,
    password,
    nama,
    email,
    is_active
) VALUES
(
    1,
    1,
    'employee_budi',
    fn_hash_password('employee123'),
    'Budi Santoso',
    'budi@backspace.com',
    TRUE
),
(
    2,
    2,
    'employee_siti',
    fn_hash_password('employee123'),
    'Siti Aminah',
    'siti@backspace.com',
    TRUE
);

INSERT INTO customer (
    id,
    username,
    password,
    nama_lengkap,
    email
) VALUES
(
    1,
    'user_andi',
    fn_hash_password('user123'),
    'Andi Pratama',
    'andi@backspace.com'
),
(
    2,
    'user_dewi',
    fn_hash_password('user123'),
    'Dewi Lestari',
    'dewi@backspace.com'
),
(
    3,
    'user_rina',
    fn_hash_password('user123'),
    'Rina Wijaya',
    'rina@backspace.com'
);

INSERT INTO kategori (id, nama_kategori) VALUES
(1, 'Keyboard Mechanical'),
(2, 'Mouse Gaming'),
(3, 'Mousepad'),
(4, 'PC Components'),
(5, 'Monitor'),
(6, 'Audio');

INSERT INTO produk (
    id,
    id_kategori,
    id_admin,
    nama_produk,
    harga,
    stok,
    deskripsi,
    status,
    deleted_at
) VALUES
(1, 1, 1, 'Keychron K2 V2', 1500000.00, 50, 'Wireless mechanical keyboard', 'active', NULL),
(2, 1, 1, 'Keychron K6 Pro', 1800000.00, 35, 'Hot-swappable wireless mechanical keyboard', 'active', NULL),
(3, 1, 2, 'Royal Kludge R87', 750000.00, 80, 'TKL mechanical keyboard for gaming', 'active', NULL),
(4, 1, 1, 'Fantech MAXFIT67', 999000.00, 25, '65% mechanical keyboard with hot-swap socket', 'active', NULL),
(5, 1, 2, 'Rexus Daxa Asteroid', 650000.00, 40, 'Local mechanical keyboard with RGB', 'active', NULL),
(6, 2, 1, 'Logitech G Pro X Superlight', 1899000.00, 40, 'Wireless esports gaming mouse', 'active', NULL),
(7, 2, 2, 'Razer DeathAdder V3', 1150000.00, 30, 'Ergonomic gaming mouse', 'active', NULL),
(8, 2, 1, 'Logitech G102 Lightsync', 299000.00, 100, 'Budget RGB gaming mouse', 'active', NULL),
(9, 2, 2, 'SteelSeries Rival 3', 450000.00, 60, 'Entry-level gaming mouse', 'active', NULL),
(10, 2, 1, 'Fantech Venom II', 250000.00, 75, 'Affordable gaming mouse', 'active', NULL),
(11, 3, 2, 'Fantech Equator Mousepad', 199000.00, 120, 'Desk-size cloth mousepad', 'active', NULL),
(12, 3, 1, 'Artisan Zero Mousepad', 650000.00, 10, 'Premium Japanese mousepad', 'active', NULL),
(13, 3, 2, 'SteelSeries QcK Medium', 150000.00, 200, 'Classic esports mousepad', 'active', NULL),
(14, 3, 1, 'Razer Gigantus V2', 350000.00, 45, 'Large gaming mousepad', 'active', NULL),
(15, 4, 1, 'Corsair Vengeance 16GB DDR4', 850000.00, 100, '16GB kit 3200MHz', 'active', NULL),
(16, 4, 2, 'Kingston Fury Beast 32GB DDR5', 1700000.00, 45, '32GB kit 5600MHz', 'active', NULL),
(17, 4, 1, 'Samsung 980 NVMe 1TB', 1200000.00, 55, 'NVMe SSD for gaming and productivity', 'active', NULL),
(18, 4, 2, 'WD Black SN850X 2TB', 2700000.00, 20, 'High-performance NVMe SSD', 'active', NULL),
(19, 4, 1, 'Intel Core i5-13400F', 3200000.00, 18, '6 performance cores + 4 efficient cores', 'active', NULL),
(20, 4, 2, 'AMD Ryzen 5 7600', 3500000.00, 15, 'Zen 4 processor for gaming', 'active', NULL),
(21, 4, 1, 'ASUS TUF Gaming B760M', 1900000.00, 12, 'Micro ATX motherboard', 'active', NULL),
(22, 4, 2, 'MSI MAG B650M Mortar', 2600000.00, 8, 'Micro ATX motherboard for Ryzen', 'active', NULL),
(23, 5, 1, 'LG UltraGear 24 Inch 144Hz', 2200000.00, 14, 'IPS gaming monitor', 'active', NULL),
(24, 5, 2, 'AOC 27G2 165Hz', 2400000.00, 9, 'IPS gaming monitor with adjustable stand', 'active', NULL),
(25, 5, 1, 'Samsung Odyssey G5 32 Inch', 3800000.00, 6, 'Curved gaming monitor', 'active', NULL),
(26, 6, 2, 'Edifier R1280T', 1100000.00, 22, 'Bookshelf speaker', 'active', NULL),
(27, 6, 1, 'Logitech Z313', 550000.00, 33, '2.1 speaker system', 'active', NULL),
(28, 6, 2, 'HyperX Cloud II', 1200000.00, 27, 'Gaming headset', 'active', NULL),
(29, 2, 1, 'Corsair Katar Pro XT', 350000.00, 0, 'Out of stock item for checkout failure testing', 'active', NULL),
(30, 1, 2, 'Razer BlackWidow V3', 1700000.00, 5, 'Low stock item for stock movement testing', 'active', NULL),
(31, 1, 1, 'Legacy Mechanical Keyboard', 600000.00, 5, 'Soft-deleted item for testing', 'active', CURRENT_TIMESTAMP);

SELECT setval(
    pg_get_serial_sequence('role', 'id'),
    COALESCE((SELECT MAX(id) FROM role), 1),
    TRUE
);

SELECT setval(
    pg_get_serial_sequence('admin', 'id'),
    COALESCE((SELECT MAX(id) FROM admin), 1),
    TRUE
);

SELECT setval(
    pg_get_serial_sequence('customer', 'id'),
    COALESCE((SELECT MAX(id) FROM customer), 1),
    TRUE
);

SELECT setval(
    pg_get_serial_sequence('kategori', 'id'),
    COALESCE((SELECT MAX(id) FROM kategori), 1),
    TRUE
);

SELECT setval(
    pg_get_serial_sequence('produk', 'id'),
    COALESCE((SELECT MAX(id) FROM produk), 1),
    TRUE
);