CREATE OR REPLACE VIEW v_laporan_penjualan AS
SELECT 
    p.id AS pesanan_id,
    c.nama_lengkap AS customer_name,
    a.nama AS cashier_name,
    p.tanggal_pesanan,
    p.total_harga,
    p.status,
    COUNT(dp.id) AS total_items,
    SUM(dp.jumlah) AS total_quantity
FROM pesanan p
JOIN customer c ON p.id_customer = c.id
LEFT JOIN admin a ON p.id_admin = a.id
LEFT JOIN detail_pesanan dp ON p.id = dp.id_pesanan
GROUP BY p.id, c.nama_lengkap, a.nama, p.tanggal_pesanan, p.total_harga, p.status;