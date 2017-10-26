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

CREATE or replace FUNCTION dataset.idconfig(text) RETURNS int AS $f$
     SELECT id FROM dataset.meta WHERE tmp_name=$1;
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- 

CREATE VIEW dataset.vw_meta_summary AS
  SELECT id, tmp_name, info->>'primaryKey' as pkey, info->>'lang' as lang,
    jsonb_array_length(info#>'{schema,fields}') as n_fields 
    -- jsonb_pretty(info) as show_info 
  FROM dataset.meta
;


CREATE VIEW dataset.vw_meta_fields AS 
  SELECT id, tmp_name, f->>'name' as field_name, f->>'type' as field_type,
         f->>'description' as field_desc
  FROM (
    SELECT id, tmp_name, jsonb_array_elements(info#>'{schema,fields}') as f 
    FROM dataset.meta
  ) t
;



