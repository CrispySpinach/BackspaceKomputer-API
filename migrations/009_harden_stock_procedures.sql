-- Business validation stays in PostgreSQL; a failed CALL rolls back all changes.
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
    IF NOT EXISTS (
        SELECT 1 FROM admin a JOIN role r ON r.id = a.id_role
        WHERE a.id = p_id_admin AND a.is_active AND r.nama_role IN ('admin', 'cashier')
    ) THEN
        RAISE EXCEPTION 'Active cashier or admin required' USING ERRCODE = '42501';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'Items must be an array' USING ERRCODE = '22023';
    END IF;
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Items cannot be empty' USING ERRCODE = '22023';
    END IF;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF jsonb_typeof(v_item) <> 'object'
           OR COALESCE(v_item->>'id_produk', '') !~ '^[1-9][0-9]*$'
           OR COALESCE(v_item->>'jumlah', '') !~ '^[1-9][0-9]*$'
           OR (v_item->>'id_produk')::NUMERIC > 2147483647
           OR (v_item->>'jumlah')::NUMERIC > 2147483647 THEN
            RAISE EXCEPTION 'Product and quantity must be positive integers' USING ERRCODE = '22023';
        END IF;
    END LOOP;

    -- Stable lock ordering prevents opposite cart orders from deadlocking.
    PERFORM p.id FROM produk p
    WHERE p.id IN (SELECT (item->>'id_produk')::INT FROM jsonb_array_elements(p_items) item)
    ORDER BY p.id FOR UPDATE;

    INSERT INTO pesanan (id_customer, id_admin, total_harga, status)
    VALUES (p_id_customer, p_id_admin, 0, 'pending') RETURNING id INTO v_id_pesanan;
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
        VALUES (v_id_produk, p_id_admin, v_id_pesanan, 'penjualan', v_jumlah, 'Checkout Penjualan');
    END LOOP;
    UPDATE pesanan SET status = 'selesai' WHERE id = v_id_pesanan;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_restock_product(
    IN p_id_produk INT, IN p_id_admin INT, IN p_jumlah INT, IN p_catatan TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM admin a JOIN role r ON r.id = a.id_role
        WHERE a.id = p_id_admin AND a.is_active AND r.nama_role IN ('admin', 'storage')
    ) THEN
        RAISE EXCEPTION 'Active storage employee or admin required' USING ERRCODE = '42501';
    END IF;
    PERFORM id FROM produk WHERE id = p_id_produk AND deleted_at IS NULL AND status = 'active' FOR UPDATE;
    IF NOT FOUND OR p_catatan IS NOT NULL AND length(p_catatan) > 255 THEN
        RAISE EXCEPTION 'Invalid product or note' USING ERRCODE = '22023';
    END IF;
    INSERT INTO stok_movement (id_produk, id_admin, jenis, jumlah, catatan)
    VALUES (p_id_produk, p_id_admin, 'masuk', p_jumlah, p_catatan);
END;
$$;
