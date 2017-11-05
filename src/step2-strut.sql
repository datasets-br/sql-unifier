DROP SCHEMA IF EXISTS dataset CASCADE; -- danger when reusing

CREATE SCHEMA dataset;

DROP TABLE IF EXISTS dataset.meta CASCADE;
CREATE TABLE dataset.meta (
	id serial PRIMARY KEY,
	tmp_name text,
	kx_fields text[],
	kx_types text[],
	info JSONb
);

DROP TABLE IF EXISTS dataset.big CASCADE;
CREATE TABLE dataset.big (
  id bigserial not null primary key,
  source int NOT NULL REFERENCES dataset.meta(id) ON DELETE CASCADE, -- Dataset ID and metadata.
  key text,  -- Optional. Dataset primary key (converted to text).
  c JSONb CHECK(jsonb_array_length(c)>0), -- All dataset columns here, as exact copy of CSV line!
  UNIQUE(source,key)
);


-- -- --
-- -- --
-- Essential functions

CREATE or replace FUNCTION dataset.idconfig(text) RETURNS int AS $f$
     SELECT id FROM dataset.meta WHERE tmp_name=$1;
$f$ LANGUAGE SQL IMMUTABLE;


-- -- --
-- -- --
-- VIEWS



CREATE VIEW dataset.vw_meta_summary_aux AS
  SELECT id, tmp_name, info->'primaryKey' as pkey, info->>'lang' as lang,
    jsonb_array_length(info#>'{schema,fields}') as n_fields
    -- jsonb_pretty(info) as show_info
  FROM dataset.meta
;
CREATE VIEW dataset.vw_meta_summary AS
  SELECT id, tmp_name, pkey::text, lang, n_fields FROM dataset.vw_meta_summary_aux
;
CREATE VIEW dataset.vw_jmeta_summary AS
  SELECT jsonb_agg(to_jsonb(v)) AS jmeta_summary
	FROM dataset.vw_meta_summary_aux v
;

CREATE VIEW dataset.vw_meta_fields AS
  SELECT id, tmp_name, f->>'name' as field_name, f->>'type' as field_type,
         f->>'description' as field_desc
  FROM (
    SELECT id, tmp_name, jsonb_array_elements(info#>'{schema,fields}') as f
    FROM dataset.meta
  ) t
;
CREATE VIEW dataset.vw_jmeta_fields AS
  -- use SELECT jsonb_agg(jmeta_fields) as j FROM dataset.vw_jmeta_fields WHERE dataset_id IN (1,3);
	SELECT id AS dataset_id,
	  jsonb_build_object('dataset', dataset, 'fields', json_agg(field)) AS jmeta_fields
	FROM (
	  SELECT id,
		     jsonb_build_object('id',id, 'tmp_name',tmp_name) as dataset,
	       jsonb_build_object('field_name',field_name, 'field_type',field_type, 'field_desc',field_desc) as field
	  FROM dataset.vw_meta_fields
	) t
	GROUP BY id, dataset
;


-- -- --
-- -- --
-- LIB for dataset-schema structures, toolkit.


/**
 * Get metadata pieces and transforms it into text-array.
 * Used in cache-refresh etc.
 */
CREATE or replace FUNCTION dataset.metaget_schema_field(
  p_info JSONb, p_field text
) RETURNS text[] AS $f$
  SELECT array_agg(x)
  FROM (  -- need to "cast" from record to table, to use array_agg
    SELECT (jsonb_array_elements($1#>'{schema,fields}')->>p_field)::text
  ) t(x)
$f$ language SQL IMMUTABLE;
CREATE or replace FUNCTION dataset.metaget_schema_field(
  p_name text, p_field text
) RETURNS text[] AS $f$
  SELECT dataset.metaget_schema_field(info,$2)
  FROM  dataset.meta
  WHERE tmp_name=$1
$f$ language SQL IMMUTABLE;

/**
 * Float-Sum of a slice of columns of the table dataset.big, avoiding nulls.
 */
CREATE or replace FUNCTION dataset.fltsum_colslice(
  p_j JSONb,   -- from dataset.big.c
  p_ini int DEFAULT 0,  -- first column of the slice, starting with 0
  p_fim int DEFAULT NULL  -- last column of the slice, NULL for all cols
) RETURNS float  AS $f$
DECLARE
     i int;
     tsum float :=0.0;
BEGIN
  IF p_fim IS NULL OR p_fim<0 THEN p_fim:=jsonb_array_length($1); END IF;
  FOR i IN p_ini..p_fim LOOP
     tsum := tsum + COALESCE( ($1->>i)::float, 0 );
  END LOOP;
  RETURN tsum;
END;
$f$ LANGUAGE plpgsql IMMUTABLE;

/**
 * Bigint-Sum of a slice of columns of the table dataset.big, avoiding nulls.
 */
CREATE or replace FUNCTION dataset.intsum_colslice(
  p_j JSONb,   -- from dataset.big.c
  p_ini int DEFAULT 0,  -- first column of the slice, starting with 0
  p_fim int DEFAULT NULL  -- last column of the slice, NULL for all cols
) RETURNS bigint  AS $f$
DECLARE
     i int;
     tsum bigint :=0;
BEGIN
  IF p_fim IS NULL OR p_fim<0 THEN p_fim:=jsonb_array_length($1); END IF;
  FOR i IN p_ini..p_fim LOOP
     tsum := tsum + COALESCE( ($1->>i)::bigint, 0 );
  END LOOP;
  RETURN tsum;
END;
$f$ LANGUAGE plpgsql IMMUTABLE;
