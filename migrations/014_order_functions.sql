CREATE FUNCTION fn_orders(k TEXT, actor INT, target INT, lim INT, offst INT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE result JSONB;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['customer','admin','cashier']);
 IF target IS NULL THEN
  SELECT COALESCE(jsonb_agg(to_jsonb(o)),'[]') INTO result FROM
   (SELECT * FROM pesanan WHERE (k='employee' OR id_customer=actor)
    ORDER BY id DESC LIMIT greatest(1,least(lim,100)) OFFSET greatest(offst,0)) o;
 ELSE
  SELECT to_jsonb(o)||jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id) FROM detail_pesanan d WHERE id_pesanan=o.id),'[]'))
   INTO result FROM pesanan o WHERE id=target AND (k='employee' OR id_customer=actor);
  IF result IS NULL THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='P0002'; END IF;
 END IF;
 RETURN result;
END; $$;

CREATE FUNCTION fn_place_order(k TEXT, actor INT, customer_id INT, items JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE target INT; item JSONB; product_id INT; quantity INT; price NUMERIC; stock INT; employee_id INT;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['customer','admin','cashier']);
 IF k='customer' THEN
  IF customer_id IS NOT NULL AND customer_id<>actor THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501'; END IF;
  customer_id:=actor;
 ELSE employee_id:=actor;
 END IF;
 PERFORM id FROM customer WHERE id=customer_id AND is_active FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found' USING ERRCODE='P0002'; END IF;
 IF items IS NULL OR jsonb_typeof(items)<>'array' THEN RAISE EXCEPTION 'Items array required' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(items) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Cart size invalid' USING ERRCODE='22023'; END IF;
 FOR item IN SELECT * FROM jsonb_array_elements(items) LOOP
  IF COALESCE(item->>'id_produk','') !~ '^[1-9][0-9]*$' OR COALESCE(item->>'jumlah','') !~ '^[1-9][0-9]*$' THEN
   RAISE EXCEPTION 'Positive integer required' USING ERRCODE='22023'; END IF;
  product_id:=(item->>'id_produk')::INT; quantity:=(item->>'jumlah')::INT;
 END LOOP;
 PERFORM id FROM produk WHERE id IN (SELECT (v->>'id_produk')::INT FROM jsonb_array_elements(items) v) ORDER BY id FOR UPDATE;
 INSERT INTO pesanan(id_customer,id_admin,status) VALUES(customer_id,employee_id,'pending') RETURNING id INTO target;
 FOR item IN SELECT * FROM jsonb_array_elements(items) LOOP
  product_id:=(item->>'id_produk')::INT; quantity:=(item->>'jumlah')::INT;
  SELECT harga,stok INTO price,stock FROM produk WHERE id=product_id AND deleted_at IS NULL AND status='active';
  IF NOT FOUND OR stock<quantity THEN RAISE EXCEPTION 'Insufficient stock' USING ERRCODE='22023'; END IF;
  INSERT INTO detail_pesanan(id_pesanan,id_produk,jumlah,harga_satuan) VALUES(target,product_id,quantity,price);
  INSERT INTO stok_movement(id_produk,id_admin,id_customer,id_pesanan,jenis,jumlah,catatan)
  VALUES(product_id,employee_id,CASE WHEN k='customer' THEN actor END,target,'penjualan',quantity,'Checkout');
 END LOOP;
 UPDATE pesanan SET status='selesai' WHERE id=target;
 RETURN fn_orders(k,actor,target,1,0);
END; $$;

CREATE FUNCTION fn_cancel_order(k TEXT, actor INT, target INT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE order_status TEXT; item RECORD;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['customer','admin','cashier']);
 SELECT status INTO order_status FROM pesanan WHERE id=target AND (k='employee' OR id_customer=actor) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order not found' USING ERRCODE='P0002'; END IF;
 IF order_status='dibatalkan' THEN RAISE EXCEPTION 'Already cancelled' USING ERRCODE='23505'; END IF;
 PERFORM id FROM produk WHERE id IN (SELECT id_produk FROM detail_pesanan WHERE id_pesanan=target) ORDER BY id FOR UPDATE;
 FOR item IN SELECT id_produk,sum(jumlah)::INT AS jumlah FROM detail_pesanan WHERE id_pesanan=target GROUP BY id_produk ORDER BY id_produk LOOP
  INSERT INTO stok_movement(id_produk,id_admin,id_customer,id_pesanan,jenis,jumlah,catatan)
  VALUES(item.id_produk,CASE WHEN k='employee' THEN actor END,CASE WHEN k='customer' THEN actor END,target,'masuk',item.jumlah,'Order cancellation');
 END LOOP;
 UPDATE pesanan SET status='dibatalkan' WHERE id=target;
 RETURN fn_orders(k,actor,target,1,0);
END; $$;
