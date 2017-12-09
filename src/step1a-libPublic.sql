CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()
CREATE EXTENSION IF NOT EXISTS unaccent; -- for unaccent()
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for digest()

-- PUBLIC SCHEMA functions

/**
 * A good workaround solution for an old problem,
 * @see https://stackoverflow.com/a/20934099/287948
 */
 CREATE or replace FUNCTION ROUND(float,int) RETURNS NUMERIC AS $$
    SELECT ROUND($1::numeric,$2);
 $$ language SQL IMMUTABLE;

/**
 * A general solution for an old problem,
 * @see https://stackoverflow.com/a/20934099/287948
 */
CREATE or replace FUNCTION ROUND(float, text, int DEFAULT 0)
RETURNS FLOAT AS $$
   SELECT CASE WHEN $2='dec'
               THEN ROUND($1::numeric,$3)::float
               -- ... WHEN $2='hex' THEN ... WHEN $2='bin' THEN... complete!
               ELSE 'NaN'::float  -- like an error message
           END;
$$ language SQL IMMUTABLE;

CREATE or replace FUNCTION jsonb_array_totext(JSONb) RETURNS text[] AS $$
  -- workaround to convert json array into SQL text[]
  -- ideal is PostgreSQL to (internally) convert json array into SQL-array of JSONb values
  SELECT array_agg(x) FROM jsonb_array_elements_text($1) t(x);
$$ language SQL IMMUTABLE;

--  pthe remain of the array_pop. Ideal a function that changes array and pop it
CREATE or replace FUNCTION array_pop_off(ANYARRAY) RETURNS ANYARRAY AS $$ SELECT $1[2:array_length($1,1)]; $$ LANGUAGE sql IMMUTABLE;

CREATE or replace FUNCTION array_distinct(
      -- From https://stackoverflow.com/a/36727422/287948
      anyarray, -- input array
      boolean DEFAULT false -- flag to ignore nulls
) RETURNS anyarray AS $f$
      SELECT array_agg(DISTINCT x)
      FROM unnest($1) t(x)
      WHERE CASE WHEN $2 THEN x IS NOT NULL ELSE true END;
$f$ LANGUAGE SQL IMMUTABLE;

/**
 * From my old SwissKnife Lib. For pg 9.3+ try to_regclass()::text ...
 * Check and normalize to array the free-parameter relation-name.
 * Input options: (name); (name,schema), ("schema.name"). Ignores schema2 in ("schema.name",schema2).
 * @returns array[schemaName,tableName]
 */
CREATE or replace FUNCTION relname_to_array(text,text default NULL) RETURNS text[] AS $f$
     SELECT array[n.nspname::text, c.relname::text]
     FROM   pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace,
            regexp_split_to_array($1,'\.') t(x) -- not work with quoted names
     WHERE  CASE
              WHEN COALESCE(x[2],'')>'' THEN n.nspname = x[1]      AND c.relname = x[2]
              WHEN $2 IS NULL THEN           n.nspname = 'public'  AND c.relname = $1
              ELSE                           n.nspname = $2        AND c.relname = $1
            END
$f$ language SQL IMMUTABLE;

CREATE or replace FUNCTION relname_exists(text,text default NULL) RETURNS boolean AS $wrap$
  SELECT relname_to_array($1,$2) IS NOT NULL
$wrap$ language SQL IMMUTABLE;

CREATE or replace FUNCTION relname_normalized(text,text default NULL,boolean DEFAULT true) RETURNS text AS $wrap$
  SELECT COALESCE(array_to_string(relname_to_array($1,$2), '.'), CASE WHEN $3 THEN '' ELSE NULL END)
$wrap$ language SQL IMMUTABLE;


/**
 * Build an array-dictionary to associate indexes. Use f(a)->>'name' to obtain index.
 * Example: array['a','b','x'] is converted to {"a":1,"b":2,"x":3}
 */
CREATE or replace FUNCTION array_jsonb_dic(anyarray) RETURNS JSONb AS $f$
  SELECT jsonb_object_agg(a,ordinality)
  FROM (
    SELECT a, ordinality   FROM   unnest($1) WITH ORDINALITY a
  ) t
$f$ language SQL IMMUTABLE;


------
--  JSON builder to aggregate into an object, like jsonb_object_agg(), but using existent pairs
-- For olds jsonb_object_cat(jsonb,jsonb) and jsonb_agg_object_cat, see bag.agg()


-- -- -- -- --
-- DISK-USAGE

-- DANGER, not reliable!! Check if table_size make sense!
CREATE or replace VIEW pgvw_class_usage AS  --  see https://wiki.postgresql.org/wiki/Disk_Usage
  SELECT *, pg_size_pretty(table_bytes) AS table_size
  FROM (
	SELECT nspname , relname, total_bytes
	       , total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
	FROM (
		SELECT nspname , relname
		  , pg_total_relation_size(c.oid) AS total_bytes
		  , pg_indexes_size(c.oid) AS index_bytes
		  , pg_total_relation_size(reltoastrelid) AS toast_bytes
		FROM pg_class c
		LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
		WHERE relkind = 'r'
	) a
  ) t
  ORDER BY 1,2
; -- eg. SELECT * FROM pgvw_class_usage WHERE relname='big' AND nspname='dataset';

CREATE or replace VIEW pgvw_nsclass_usage AS
  SELECT *, pg_size_pretty(table_bytes) as table_size
  FROM (
    SELECT nspname,
           count(*) as n_tables,
           sum(total_bytes) as total_bytes, sum(table_bytes) as table_bytes
    FROM pgvw_class_usage
    GROUP BY nspname
  ) t
; -- eg. SELECT * FROM pgvw_nsclass_usage WHERE nspname='dataset';
