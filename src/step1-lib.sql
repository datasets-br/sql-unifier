/**
 * (no essential functions here, revove it from project!?)
 *
 * Useful functions library, to analyse or normalize CSV cells.
 *
 */

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- for metaphone() and levenshtein()
CREATE EXTENSION IF NOT EXISTS unaccent; -- for unaccent()
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for digest()


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

--  pthe remain of the array_pop. Ideal a function that changes array and pop it
CREATE FUNCTION array_pop_off(ANYARRAY) RETURNS ANYARRAY AS $$ SELECT $1[2:array_length($1,1)]; $$ LANGUAGE sql IMMUTABLE;

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

-- -- -- -- --
-- DISK-USAGE

CREATE VIEW pgvw_class_usage AS  --  see https://wiki.postgresql.org/wiki/Disk_Usage
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

-------------
-------------
----- HASH functions, to preserve name-id correspondence in the TUTORIALS and view names

CREATE or replace FUNCTION lib.sha1_cut7(p_word text) RETURNS int AS $f$
  -- About precise choice of truncation, see https://stackoverflow.com/q/4784335
  SELECT CASE WHEN $1='' THEN  0  ELSE ('x' || lpad(
      substr(encode(digest($1, 'sha1'), 'hex'), 1, 7)
      , 8, '0'
    ))::bit(32)::int END
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION lib.hash_digits(
  p_word text,
  p_digits int DEFAULT 2,
  p_step int DEFAULT 2 -- minimal 2 to cut  never-zero-first
) RETURNS text AS $f$
  -- 0,1,2,..9,10,12,...,99,100,101,... Never 00 pad.
  SELECT CASE
      WHEN p_word IS NULL OR p_digits<1 OR p_step<2 OR p_step>6 THEN NULL
      WHEN p_word='' THEN '0'
      WHEN substr(x,1,1)='0' THEN  lib.hash_digits(p_word,p_digits,p_step+1)
      ELSE x
    END
  FROM (
    SELECT substr(i::text, p_step, p_digits) as x, i FROM (SELECT lib.sha1_cut7(p_word)) r(i)
  ) t
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION lib.hash_digits_addnew(p_word text, p_list int[]) RETURNS int AS $f$
  -- Heuristic to good choice of minimal digits in hashed ID.
  -- for ns_id of dataset.ns, so we expect less tham 100 naspaces... but here work fine to 999
  -- see also n/k at https://en.wikipedia.org/wiki/Hash_table#Key_statistics
DECLARE
  len int;
  digits int;
  n int; -- new hash
  flag boolean;
BEGIN
  len    := array_length(p_list,1);
  digits := CASE WHEN len>9 THEN (CASE WHEN len>99 THEN 3 ELSE 2 END) ELSE 1 END; -- with coherence hypotesis for each id
  n      := lib.hash_digits(p_word,digits)::int;
  flag   := (p_list is not null AND len>0 AND n=ANY(p_list));
  IF flag THEN
    n    := lib.sha1_cut7(p_word) % (10*digits); -- like to use other hash, before +1
    flag := (n=ANY(p_list));
    IF flag AND ((digits=1 AND len>6) OR (digits=2 AND len>70)) THEN
        -- heuristic to reduce normal collisions at ~50%
      n    := lib.hash_digits(p_word,digits+1)::int;
      flag := (n=ANY(p_list));
    END IF;
    IF flag THEN
      SELECT min(x) INTO n
      FROM (SELECT unnest(p_list)+1 as x) t WHERE x NOT IN (SELECT unnest(p_list));
    END IF; -- flag2
  END IF; -- flag1
  RETURN n;
END
$f$ LANGUAGE PLpgSQL IMMUTABLE;
