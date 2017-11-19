/**
 * (no essential functions here, revove it from project!?)
 *
 * Useful functions library, to analyse or normalize CSV cells.
 *
 */

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()
CREATE EXTENSION IF NOT EXISTS unaccent; -- for unaccent()

DROP SCHEMA lib CASCADE;  -- caution (!) with existing libs
CREATE SCHEMA lib;


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
 */
CREATE or replace FUNCTION array_json_dic(anyarray) RETURNS JSON AS $f$
  SELECT json_object_agg(a,ordinality)
  FROM (
    SELECT a, ordinality   FROM   unnest($1) WITH ORDINALITY a
  ) t
$f$ language SQL IMMUTABLE;
/**
 * Build an array-dictionary to associate indexes. Use f(a)->>'name' to obtain index.
 */
CREATE or replace FUNCTION array_jsonb_dic(anyarray) RETURNS JSONb AS $f$
  SELECT jsonb_object_agg(a,ordinality)
  FROM (
    SELECT a, ordinality   FROM   unnest($1) WITH ORDINALITY a
  ) t
$f$ language SQL IMMUTABLE;

CREATE TABLE pgvw_tables_schemas AS
  SELECT schemaname, pg_size_pretty(t.taille::bigint) AS taille_table, pg_size_pretty(t.taille_totale::bigint) AS taille_totale_table
    FROM (SELECT schemaname,
                 sum(pg_relation_size(schemaname || '.' || tablename)) AS taille,
                 sum(pg_total_relation_size(schemaname || '.' || tablename)) AS taille_totale
            FROM pg_tables
            WHERE relname_exists(tablename,schemaname)   -- see note
  GROUP BY schemaname) as t ORDER BY taille_totale DESC
; -- eg. SELECT * FROM pgvw_tables_schemas WHERE schemaname='test123';

CREATE TABLE pgvw_tables AS
  SELECT schemaname||'.'||tablename as relname, tablespace, pg_size_pretty(taille) AS taille_table, pg_size_pretty(taille_totale) AS taille_totale_table
    FROM (SELECT *,
                 pg_relation_size(schemaname || '.' || tablename) AS taille,
                 pg_total_relation_size(schemaname || '.' || tablename) AS taille_totale
            FROM pg_tables) AS tables
            WHERE relname_exists(tablename,schemaname)   -- see note
   ORDER BY taille_totale DESC
; -- eg. SELECT * FROM pgvw_tables WHERE relname='dataset.big';

-- -- -- -- --
-- DISK-USAGE

CREATE VIEW pgvw_class_usage AS
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

CREATE VIEW pgvw_nsclass_usage AS
  SELECT *, pg_size_pretty(table_bytes) as table_size
  FROM (
    SELECT nspname,
           count(*) as n_tables,
           sum(total_bytes) as total_bytes, sum(table_bytes) as table_bytes
    FROM pgvw_class_usage
    GROUP BY nspname
  ) t
; -- eg. SELECT * FROM pgvw_nsclass_usage WHERE nspname='dataset';


------------------------
-- lIB

CREATE or replace FUNCTION lib.jtype_to_sql(text) RETURNS text AS $f$
	SELECT case
		WHEN $1='string' OR $1='null' THEN 'text'
		WHEN $1='number' THEN 'numeric'
		WHEN $1='array' THEN 'text[]'
		ELSE $1
	END
$f$ language SQL;


CREATE or replace FUNCTION lib.pg_varname(text) RETURNS text AS $f$
  SELECT regexp_replace(trim(regexp_replace( unaccent($1) , '[^\w0-9\(\)]+', '_', 'g'),'_'),'[\(\)_]+','_', 'g')
	--SELECT trim(regexp_replace( unaccent($1) , '[^\w0-9]+', '_', 'g'), '_')
$f$ language SQL;

CREATE or replace FUNCTION lib.pg_varname(text[]) RETURNS text[] AS $f$
	SELECT array_agg(lib.pg_varname(x)) FROM unnest($1) t(x);
$f$ language SQL;


/**
 * Percent avoiding divisions by zero.
 */
CREATE or replace FUNCTION lib.div_percent(
  float, float, -- a/b
  int DEFAULT NULL, -- 0-N decimal places or NULL for full
  boolean DEFAULT true -- returns zero when NULL inputs, else returns NULL
) RETURNS float AS $f$
   SELECT CASE
      WHEN $1 IS NULL OR $2 IS NULL THEN (CASE WHEN $4 THEN 0.0 ELSE NULL END)
      WHEN $1=0.0 THEN 0.0
      WHEN $2=0.0 THEN 'Infinity'::float
      ELSE CASE
        WHEN $3 IS NOT NULL AND $3>=0 THEN ROUND(100.0*$1/$2,$3)::float
        ELSE 100.0*$1/$2
      END
   END
$f$ language SQL IMMUTABLE;
CREATE or replace FUNCTION lib.div_percent(
  bigint, bigint, int DEFAULT NULL
) RETURNS float AS $wrap$
   SELECT lib.div_percent($1::float, $2::float, $3)
$wrap$ language SQL IMMUTABLE;
CREATE or replace FUNCTION lib.div_percent_int(bigint,bigint) RETURNS bigint AS $wrap$
   SELECT lib.div_percent($1::float, $2::float, 0)::bigint
$wrap$ language SQL IMMUTABLE;

-- LIB SCHEMA functions
-- -- -- -- -- --
-- Normalize and convert to integer-ranges, for postalCode_ranges.
-- See section "Preparation" at README.

CREATE or replace FUNCTION lib.csvranges_to_int4ranges(
  p_range text
) RETURNS int4range[] AS $f$
   SELECT ('{'||
      regexp_replace( translate($1,' -',',') , '\[(\d+),(\d+)\]', '"[\1,\2]"', 'g')
   || '}')::int4range[];
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION lib.int4ranges_to_csvranges(
  p_range int4range[]
) RETURNS text AS $f$
   SELECT translate($1::text,',{}"',' ');
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION lib.normalizeterm(
	--
	-- Converts string into standard sequence of lower-case words.
	--
	text,       		-- 1. input string (many words separed by spaces or punctuation)
	text DEFAULT ' ', 	-- 2. output separator
	int DEFAULT 320,	-- 3. max lenght of the result (system limit)
	p_sep2 text DEFAULT ' , ' -- 4. output separator between terms
) RETURNS text AS $f$
  SELECT  substring(
	LOWER(TRIM( regexp_replace(  -- for review: regex(regex()) for ` , , ` remove
		trim(regexp_replace($1,E'[\\n\\r \\+/,;:\\(\\)\\{\\}\\[\\]="\\s ]*[\\+/,;:\\(\\)\\{\\}\\[\\]="]+[\\+/,;:\\(\\)\\{\\}\\[\\]="\\s ]*|[\\s ]+[–\\-][\\s ]+',
				   p_sep2, 'g'),' ,'),   -- s*ps*|s-s
		E'[\\s ;\\|"]+[\\.\'][\\s ;\\|"]+|[\\s ;\\|"]+',    -- s.s|s
		$2,
		'g'
	), $2 )),
  1,$3
  );
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION lib.msgcut(
  p_msg text, p_cutAt int DEFAULT 60
) RETURNS text AS $f$
  SELECT CASE WHEN $1=s THEN $1 ELSE s||'...' END FROM (SELECT substring($1,1,$2)) t(s);
$f$ LANGUAGE SQL IMMUTABLE;
