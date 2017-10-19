DROP SCHEMA IF EXISTS dataset CASCADE; -- danger when resuing

CREATE SCHEMA dataset;

DROP TABLE IF EXISTS dataset.confs CASCADE;
CREATE TABLE dataset.confs (
	id serial PRIMARY KEY,
	tmp_name text,
	kx_fields text[],
	kx_types text[],
	info JSONb
);

DROP TABLE IF EXISTS dataset.big CASCADE;
CREATE TABLE dataset.big (
  id bigserial not null primary key,
  source int NOT NULL REFERENCES dataset.confs(id) ON DELETE CASCADE,
  key text,  -- opcional
  c JSONb,
  UNIQUE(source,key)
);

-- -- -- 

CREATE or replace FUNCTION dataset.idconfig(text) RETURNS int AS $f$
     SELECT id FROM dataset.confs WHERE tmp_name=$1;
$f$ LANGUAGE SQL IMMUTABLE;


-- -- -- 

CREATE VIEW dataset.vw_conf_summary AS 
  SELECT id, tmp_name, info->>'primaryKey' as pkey, info->>'lang' as lang,
    jsonb_array_length(info#>'{schema,fields}') as n_fields 
    -- jsonb_pretty(info) as show_info 
  FROM dataset.confs
;


CREATE VIEW dataset.vw_conf_fields AS 
  SELECT id, tmp_name, f->>'name' as field_name, f->>'type' as field_type,
         f->>'description' as field_desc
  FROM (
    SELECT id, tmp_name, jsonb_array_elements(info#>'{schema,fields}') as f 
    FROM dataset.confs
  ) t
;



