-- A CALL is atomic in PostgreSQL's implicit transaction. Errors roll back the
-- entire statement. No COMMIT/ROLLBACK inside an EXCEPTION subtransaction.
CREATE OR REPLACE PROCEDURE sp_process_checkout(
    IN p_id_customer INT, IN p_id_admin INT, IN p_items JSONB
)
LANGUAGE plpgsql AS $$
DECLARE
    v_id_pesanan INT;
    v_item JSONB;
    v_id_produk INT;
    v_jumlah INT;
    v_harga DECIMAL(10, 2);
    v_current_stok INT;
BEGIN
    INSERT INTO pesanan (id_customer, id_admin, total_harga, status)
    VALUES (p_id_customer, p_id_admin, 0, 'pending')
    RETURNING id INTO v_id_pesanan;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_id_produk := (v_item->>'id_produk')::INT;
        v_jumlah := (v_item->>'jumlah')::INT;
        SELECT stok, harga INTO v_current_stok, v_harga FROM produk
        WHERE id = v_id_produk AND deleted_at IS NULL AND status = 'active';
        IF NOT FOUND OR v_current_stok < v_jumlah THEN
            RAISE EXCEPTION 'Product unavailable or insufficient stock' USING ERRCODE = '22023';
        END IF;
        INSERT INTO detail_pesanan (id_pesanan, id_produk, jumlah, harga_satuan)
        VALUES (v_id_pesanan, v_id_produk, v_jumlah, v_harga);
        INSERT INTO stok_movement (id_produk, id_admin, id_pesanan, jenis, jumlah, catatan)
        VALUES (v_id_produk, COALESCE(p_id_admin, 1), v_id_pesanan, 'penjualan', v_jumlah, 'Checkout Penjualan');
    END LOOP;
    UPDATE pesanan SET status = 'selesai' WHERE id = v_id_pesanan;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_restock_product(
    IN p_id_produk INT, IN p_id_admin INT, IN p_jumlah INT, IN p_catatan TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO stok_movement (id_produk, id_admin, id_pesanan, jenis, jumlah, catatan)
    VALUES (p_id_produk, p_id_admin, NULL, 'masuk', p_jumlah, p_catatan);
END;
$$;
