CREATE FUNCTION fn_require_role(k TEXT, actor INT, roles TEXT[]) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
 IF NOT COALESCE((fn_actor(k,actor)->>'role')=ANY(roles),FALSE) THEN
  RAISE EXCEPTION 'Forbidden' USING ERRCODE='42501';
 END IF;
END; $$;

CREATE FUNCTION fn_profile(k TEXT, actor INT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE result JSONB;
BEGIN
 IF fn_actor(k,actor) IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
 IF k='customer' THEN SELECT to_jsonb(c)-'password' INTO result FROM customer c WHERE id=actor;
 ELSE SELECT to_jsonb(a)-'password' INTO result FROM admin a WHERE id=actor; END IF;
 RETURN result;
END; $$;

CREATE FUNCTION fn_update_profile(k TEXT, actor INT, p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE merged JSONB;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['customer']);
 SELECT (to_jsonb(c)-'password') || p INTO merged FROM customer c WHERE id=actor FOR UPDATE;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p) key WHERE key NOT IN ('username','nama_lengkap','email')) THEN
  RAISE EXCEPTION 'Unsupported profile field' USING ERRCODE='22023'; END IF;
 PERFORM fn_validate_customer(merged);
 UPDATE customer SET username=btrim(merged->>'username'),nama_lengkap=btrim(merged->>'nama_lengkap'),email=merged->>'email' WHERE id=actor;
 RETURN fn_profile(k,actor);
END; $$;

CREATE FUNCTION fn_users(k TEXT, actor INT, target INT, lim INT, offst INT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE result JSONB;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['admin']);
 IF target IS NOT NULL THEN
  SELECT to_jsonb(c)-'password' INTO result FROM customer c WHERE id=target AND is_active;
  IF result IS NULL THEN RAISE EXCEPTION 'User not found' USING ERRCODE='P0002'; END IF;
 ELSE
  SELECT COALESCE(jsonb_agg(to_jsonb(c)-'password'),'[]') INTO result FROM
   (SELECT * FROM customer WHERE is_active ORDER BY id LIMIT greatest(1,least(lim,100)) OFFSET greatest(offst,0)) c;
 END IF;
 RETURN result;
END; $$;

CREATE FUNCTION fn_delete_user(k TEXT, actor INT, target INT) RETURNS JSONB LANGUAGE plpgsql AS $$
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['admin']);
 UPDATE customer SET is_active=FALSE WHERE id=target AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'User not found' USING ERRCODE='P0002'; END IF;
 RETURN jsonb_build_object('id',target,'deleted',TRUE);
END; $$;

CREATE FUNCTION fn_product(target INT) RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE result JSONB;
BEGIN
 SELECT to_jsonb(p) INTO result FROM produk p WHERE id=target AND deleted_at IS NULL AND status='active';
 IF result IS NULL THEN RAISE EXCEPTION 'Product not found' USING ERRCODE='P0002'; END IF;
 RETURN result;
END; $$;

CREATE FUNCTION fn_create_product(k TEXT, actor INT, p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE target INT; quantity INT;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['admin','storage']);
 quantity:=COALESCE((p->>'stok')::INT,0);
 IF COALESCE(length(btrim(p->>'nama_produk')),0) NOT BETWEEN 1 AND 150 OR quantity<0
 OR p->>'harga' IS NULL OR (p->>'harga')::NUMERIC<0 OR (p->>'harga')::NUMERIC>=100000000
 OR (p->>'harga')::NUMERIC<>round((p->>'harga')::NUMERIC,2) OR p->>'id_kategori' IS NULL THEN
  RAISE EXCEPTION 'Invalid product' USING ERRCODE='22023'; END IF;
 INSERT INTO produk(id_kategori,id_admin,nama_produk,harga,stok,deskripsi)
 VALUES((p->>'id_kategori')::INT,actor,btrim(p->>'nama_produk'),(p->>'harga')::NUMERIC,0,p->>'deskripsi') RETURNING id INTO target;
 IF quantity>0 THEN CALL sp_restock_product(target,actor,quantity,'Initial stock'); END IF;
 RETURN fn_product(target);
END; $$;

CREATE FUNCTION fn_add_stock(k TEXT, actor INT, target INT, quantity INT, note TEXT) RETURNS JSONB LANGUAGE plpgsql AS $$
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['admin','storage']);
 CALL sp_restock_product(target,actor,quantity,note);
 RETURN fn_product(target);
END; $$;

CREATE FUNCTION fn_delete_product(k TEXT, actor INT, target INT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE quantity INT;
BEGIN
 PERFORM fn_require_role(k,actor,ARRAY['admin','storage']);
 SELECT stok INTO quantity FROM produk WHERE id=target AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Product not found' USING ERRCODE='P0002'; END IF;
 IF quantity>0 THEN
  INSERT INTO stok_movement(id_produk,id_admin,jenis,jumlah,catatan) VALUES(target,actor,'penghapusan',quantity,'Product discontinued');
 END IF;
 UPDATE produk SET status='discontinued',deleted_at=CURRENT_TIMESTAMP WHERE id=target;
 RETURN jsonb_build_object('id',target,'deleted',TRUE);
END; $$;
