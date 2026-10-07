-- Serialize all stock movements, including manual restocks, on the product row.
CREATE OR REPLACE FUNCTION trg_populate_stock_history()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    current_stock INT;
BEGIN
    IF NEW.jumlah IS NULL OR NEW.jumlah <= 0 THEN
        RAISE EXCEPTION 'Movement quantity must be positive' USING ERRCODE = '22023';
    END IF;
    SELECT stok INTO current_stock FROM produk WHERE id = NEW.id_produk FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found' USING ERRCODE = '22023';
    END IF;
    NEW.stok_sebelum := current_stock;
    IF NEW.jenis IN ('masuk', 'penyesuaian') THEN
        NEW.stok_sesudah := current_stock + NEW.jumlah;
    ELSIF NEW.jenis IN ('keluar', 'penjualan', 'penghapusan') THEN
        NEW.stok_sesudah := current_stock - NEW.jumlah;
    ELSE
        RAISE EXCEPTION 'Invalid movement type' USING ERRCODE = '22023';
    END IF;
    IF NEW.stok_sesudah < 0 THEN
        RAISE EXCEPTION 'Insufficient stock' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
