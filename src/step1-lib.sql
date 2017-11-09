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
