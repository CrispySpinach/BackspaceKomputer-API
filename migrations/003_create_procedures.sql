CREATE OR REPLACE PROCEDURE sp_process_checkout(
    IN p_id_customer INT,
    IN p_id_admin INT, 
    IN p_items JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_pesanan INT;
    v_item JSONB;
    v_id_produk INT;
    v_jumlah INT;
    v_harga DECIMAL(10, 2);
    v_current_stok INT;
    v_id_admin_movement INT;
BEGIN
    IF p_id_admin IS NULL THEN v_id_admin_movement := 1; 
    ELSE v_id_admin_movement := p_id_admin; END IF;

    -- 1. Create Pesanan Header
    INSERT INTO pesanan (id_customer, id_admin, tanggal_pesanan, total_harga, status)
    VALUES (p_id_customer, p_id_admin, CURRENT_TIMESTAMP, 0, 'pending')
    RETURNING id INTO v_id_pesanan;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_id_produk := (v_item->>'id_produk')::INT;
        v_jumlah := (v_item->>'jumlah')::INT;

        SELECT stok, harga INTO v_current_stok, v_harga 
        FROM produk 
        WHERE id = v_id_produk AND deleted_at IS NULL AND status = 'active';

        IF v_current_stok IS NULL THEN RAISE EXCEPTION 'Product % not found or inactive', v_id_produk; END IF;
        IF v_current_stok < v_jumlah THEN RAISE EXCEPTION 'Insufficient stock for product %', v_id_produk; END IF;

        INSERT INTO detail_pesanan (id_pesanan, id_produk, jumlah, harga_satuan)
        VALUES (v_id_pesanan, v_id_produk, v_jumlah, v_harga);

        INSERT INTO stok_movement (id_produk, id_admin, id_pesanan, jenis, jumlah, catatan)
        VALUES (v_id_produk, v_id_admin_movement, v_id_pesanan, 'penjualan', v_jumlah, 'Checkout Penjualan');
    END LOOP;

    UPDATE pesanan SET status = 'selesai' WHERE id = v_id_pesanan;
    
    COMMIT; 

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE EXCEPTION 'Checkout Transaction Failed: %', SQLERRM;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_restock_product(
    IN p_id_produk INT,
    IN p_id_admin INT,
    IN p_jumlah INT,
    IN p_catatan TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO stok_movement (id_produk, id_admin, id_pesanan, jenis, jumlah, catatan)
    VALUES (p_id_produk, p_id_admin, NULL, 'masuk', p_jumlah, p_catatan);
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE EXCEPTION 'Restock Failed: %', SQLERRM;
END;
$$;