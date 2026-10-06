CREATE TRIGGER before_insert_detail_pesanan
BEFORE INSERT ON detail_pesanan
FOR EACH ROW EXECUTE FUNCTION trg_calculate_subtotal();

CREATE TRIGGER after_insert_detail_pesanan
AFTER INSERT ON detail_pesanan
FOR EACH ROW EXECUTE FUNCTION trg_update_pesanan_total();

CREATE TRIGGER before_insert_stok_movement
BEFORE INSERT ON stok_movement
FOR EACH ROW EXECUTE FUNCTION trg_populate_stock_history();

CREATE TRIGGER after_insert_stok_movement
AFTER INSERT ON stok_movement
FOR EACH ROW EXECUTE FUNCTION trg_update_product_stock();