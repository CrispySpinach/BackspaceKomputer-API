CREATE FUNCTION fn_validate_customer(p JSONB) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF COALESCE(length(btrim(p->>'username')),0) NOT BETWEEN 3 AND 50
       OR COALESCE(length(btrim(p->>'nama_lengkap')),0) NOT BETWEEN 1 AND 100
       OR COALESCE(length(p->>'email'),0) NOT BETWEEN 3 AND 100
       OR COALESCE(p->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
        RAISE EXCEPTION 'Invalid customer details' USING ERRCODE='22023';
    END IF;
    -- pgcrypto bcrypt accepts at most 72 bytes. Reject rather than truncate.
    IF p ? 'password' AND (COALESCE(octet_length(p->>'password'),0) NOT BETWEEN 8 AND 72) THEN
        RAISE EXCEPTION 'Password must contain 8 to 72 bytes' USING ERRCODE='22023';
    END IF;
END;
$$;

CREATE FUNCTION fn_register_customer(p JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE c customer;
BEGIN
    PERFORM fn_validate_customer(p);
    IF NOT p ? 'password' THEN
        RAISE EXCEPTION 'Password required' USING ERRCODE='22023';
    END IF;
    INSERT INTO customer(username,password,nama_lengkap,email)
    VALUES(btrim(p->>'username'),fn_hash_password(p->>'password'),btrim(p->>'nama_lengkap'),p->>'email') RETURNING * INTO c;
    RETURN to_jsonb(c)-'password';
END;
$$;

CREATE FUNCTION fn_actor(p_kind TEXT,p_id INT) RETURNS JSONB LANGUAGE plpgsql STABLE AS $$
DECLARE result JSONB;
BEGIN
    IF p_kind='customer' THEN
        SELECT jsonb_build_object('id',id,'kind','customer','role','customer') INTO result
        FROM customer WHERE id=p_id AND is_active;
    ELSIF p_kind='employee' THEN
        SELECT jsonb_build_object('id',a.id,'kind','employee','role',r.nama_role) INTO result
        FROM admin a JOIN role r ON r.id=a.id_role WHERE a.id=p_id AND a.is_active;
    END IF;
    RETURN result;
END;
$$;

CREATE FUNCTION fn_authenticate(p_kind TEXT,p_username TEXT,p_password TEXT)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE actor_id INT;
BEGIN
    IF p_password IS NULL OR octet_length(p_password)>72 THEN RETURN NULL; END IF;
    IF p_kind='customer' THEN
        SELECT id INTO actor_id FROM customer WHERE username=p_username AND is_active
          AND fn_verify_password(p_password,password);
    ELSIF p_kind='employee' THEN
        SELECT id INTO actor_id FROM admin WHERE username=p_username AND is_active
          AND fn_verify_password(p_password,password);
    END IF;
    RETURN fn_actor(p_kind,actor_id);
END;
$$;
