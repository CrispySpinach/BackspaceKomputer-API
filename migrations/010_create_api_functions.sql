CREATE OR REPLACE FUNCTION fn_login_admin(p_username TEXT, p_password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_valid BOOLEAN;
BEGIN
    SELECT fn_verify_password(p_password, password) INTO v_is_valid
    FROM admin
    WHERE username = p_username AND is_active = TRUE;

    RETURN COALESCE(v_is_valid, FALSE);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_produk_aktif()
RETURNS SETOF produk AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM produk
    WHERE deleted_at IS NULL AND status = 'active';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_laporan_penjualan()
RETURNS TABLE (
    pesanan_id INT,
    customer_name VARCHAR,
    cashier_name VARCHAR,
    tanggal_pesanan TIMESTAMP,
    total_harga DECIMAL,
    status VARCHAR,
    total_items BIGINT,
    total_quantity BIGINT
) AS $$
BEGIN
    RETURN QUERY SELECT * FROM v_laporan_penjualan;
END;
$$ LANGUAGE plpgsql;