ALTER TABLE customer ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;
-- Online customer orders have no employee actor; retain customer attribution.
ALTER TABLE stok_movement ALTER COLUMN id_admin DROP NOT NULL;
ALTER TABLE stok_movement ADD COLUMN id_customer INT REFERENCES customer(id);
