--- Enable Logical replication
ALTER SYSTEM SET wal_level = logical;
-- (require RDS parameter group + reboot)


-- Create DMS user
CREATE USER dms_user WITH PASSWORD 'CHANGE_ME';
GRANT rds_replication TO dms_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dms_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO dms_user;


-- Enable replica identity for full CDC (captures before/after)
ALTER TABLE public.purchases REPLICA IDENTITY FULL;