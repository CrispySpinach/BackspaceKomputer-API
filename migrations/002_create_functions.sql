CREATE OR REPLACE FUNCTION fn_hash_password(plain_password TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN crypt(plain_password, gen_salt('bf', 8));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_verify_password(plain_password TEXT, hashed_password TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (crypt(plain_password, hashed_password) = hashed_password);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_calculate_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    NEW.harga_subtotal := NEW.jumlah * NEW.harga_satuan;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_update_pesanan_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE pesanan 
    SET total_harga = total_harga + NEW.harga_subtotal 
    WHERE id = NEW.id_pesanan;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_populate_stock_history()
RETURNS TRIGGER AS $$
DECLARE
    current_stock INT;
BEGIN
    SELECT stok INTO current_stock FROM produk WHERE id = NEW.id_produk;
    
    IF current_stock IS NULL THEN
        RAISE EXCEPTION 'Product with ID % not found', NEW.id_produk;
    END IF;

    NEW.stok_sebelum := current_stock;
    
    IF NEW.jenis IN ('masuk', 'penyesuaian') THEN
        NEW.stok_sesudah := current_stock + NEW.jumlah;
    ELSIF NEW.jenis IN ('keluar', 'penjualan', 'penghapusan') THEN
        NEW.stok_sesudah := current_stock - NEW.jumlah;
    ELSE
        NEW.stok_sesudah := current_stock;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_update_product_stock()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE produk SET stok = NEW.stok_sesudah WHERE id = NEW.id_produk;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_get_revenue_by_month(p_month INT, p_year INT)
RETURNS DECIMAL AS $$
DECLARE
    total_revenue DECIMAL(12, 2);
BEGIN
    SELECT COALESCE(SUM(total_harga), 0) INTO total_revenue
    FROM pesanan
    WHERE EXTRACT(MONTH FROM tanggal_pesanan) = p_month
      AND EXTRACT(YEAR FROM tanggal_pesanan) = p_year
      AND status = 'selesai';
      
    RETURN total_revenue;
END;
$$ LANGUAGE plpgsql;