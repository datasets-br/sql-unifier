DROP SCHEMA IF EXISTS dataset CASCADE; -- danger when reusing

CREATE SCHEMA dataset;

-- -- -- --
-- VALIDATION-CHECK functions
CREATE FUNCTION dataset.makekx_urn(p_name text,p_namespace text DEFAULT '') RETURNS text AS $f$
	SELECT CASE
			WHEN $2='' OR $2 IS NULL THEN $1
			ELSE lower($2)||':'||$1
	END
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION dataset.makekx_uname(p_uname text) RETURNS text AS $f$
	SELECT  lower(lib.normalizeterm($1))
$f$ LANGUAGE SQL IMMUTABLE;

-- -- -- --
-- -- Tables

CREATE TABLE dataset.ns(
  -- Namespace
  nsid  serial NOT NULL PRIMARY KEY,
  name text NOT NULL,  -- namespace label
  dft_lang text,  -- default lang of datasets
  jinfo JSONB,    -- any metadata as description, etc.
  created date DEFAULT now(),
  UNIQUE(name)
);
INSERT INTO dataset.ns (name) VALUES (''); -- the default namespace!

-- DROP TABLE IF EXISTS dataset.meta CASCADE;
CREATE TABLE dataset.meta (
	id serial PRIMARY KEY,
	namespace text NOT NULL DEFAULT '' REFERENCES dataset.ns(name),
	name text NOT NULL, -- original dataset name or filename of the CSV

	is_canonic BOOLEAN DEFAULT false, -- for canonic or "reference datasets". Curated by community.
	sametypes_as text,  -- kx_urn of an is_canonic-dataset with same kx_types. For merge() or UNION.
	projection_of text, -- kx_urn of its is_canonic-dataset, need to map same kx_types. No canonic is a projection.

	info JSONb, -- all metadata (information) here!

	-- Cache fields generated by UPDATE or trigger.
	kx_uname text, -- the normalized name, used for  dataset.meta_id() and SQL-View labels
	kx_urn text,   -- the transparent ID for this dataset.  "$namespace:$kx_uname".
	kx_fields text[], -- field names as in info.
	kx_types text[]  -- field JSON-datatypes as in info.

	,UNIQUE(namespace,kx_uname) -- not need but same as kx_urn
	,CHECK( lib.normalizeterm(namespace)=namespace AND lower(namespace)=namespace )
	,CHECK( kx_uname=dataset.makekx_uname(name) )
	--,CHECK( kx_urn=dataset.makekx_urn(kx_urn,namespace) )
	--,CHECK( NOT(is_canonic) OR (is_canonic AND projection_of IS NULL) )
);

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

CREATE FUNCTION dataset.meta_id(text,text DEFAULT NULL) RETURNS int AS $f$
	SELECT id
	FROM dataset.meta
	WHERE (CASE WHEN $2 IS NULL THEN kx_urn=$1 ELSE kx_uname=$1 AND namespace=$2 END)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION dataset.viewname(p_dataset_id int, istab boolean=false) RETURNS text AS $f$
	-- under construction!
  SELECT CASE WHEN $2 THEN 'tmpcsv_' ELSE 'vw_' END|| kx_uname FROM dataset.meta WHERE id=$1;
$f$ language SQL IMMUTABLE;

CREATE or replace FUNCTION dataset.viewname(text,text DEFAULT NULL,boolean DEFAULT false) RETURNS text AS $f$
	SELECT dataset.viewname(id,$3)
	FROM dataset.meta
	WHERE (CASE WHEN $2 IS NULL THEN kx_urn=$1 ELSE kx_uname=$1 AND namespace=$2 END)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION dataset.meta_refresh() RETURNS TRIGGER AS $f$
BEGIN
	IF NOT EXISTS (SELECT 1 FROM dataset.ns WHERE name = NEW.namespace) THEN
		-- RAISE NOTICE '-- DEBUG02 see NS %', NEW.namespace;
		INSERT INTO dataset.ns (name) VALUES (NEW.namespace);
	END IF; -- future = controlling here the namespaces and kx_ns.
	NEW.kx_uname := dataset.makekx_uname(NEW.name);
	NEW.kx_urn   := dataset.makekx_urn(NEW.kx_uname,NEW.namespace);
	IF NEW.info IS NOT NULL THEN
	 	NEW.kx_fields := dataset.metaget_schema_field(NEW.info,'name');
		NEW.kx_types  := dataset.metaget_schema_field(NEW.info,'type');
	END IF;
	RETURN NEW;
END;
$f$ LANGUAGE plpgsql;

/**
 * Get primary-keys from standard JSON package.
 * @return array with each key.
 */
CREATE or replace FUNCTION dataset.jget_pks(JSONb) RETURNS text[] AS $f$
  SELECT  array_agg(k::text)
  FROM (
    SELECT  jsonb_array_elements( CASE
      WHEN $1->>'primaryKey' IS NULL THEN to_jsonb(array[]::text[])
      WHEN jsonb_typeof($1->'primaryKey')='string' THEN to_jsonb(array[$1->'primaryKey'])
      ELSE $1->'primaryKey'
    END )#>>'{}' as k
  ) t
$f$ language SQL IMMUTABLE;

-- -- --
-- -- --
-- Triggers
CREATE TRIGGER dataset_meta_kx  BEFORE INSERT OR UPDATE
    ON dataset.meta
		FOR EACH ROW EXECUTE PROCEDURE dataset.meta_refresh()
;

-- -- --
-- -- --
-- VIEWS
-- (name convention: "vw_" prefix for dataset-view, "v" prefix for main structure)


CREATE VIEW dataset.vmeta_summary_aux AS
  SELECT m.id, m.kx_urn as urn,  array_to_string(dataset.jget_pks(m.info),'/') as pkey, m.info->>'lang' as lang,
    jsonb_array_length(m.info#>'{schema,fields}') as n_cols, t.n_rows
    -- jsonb_pretty(info) as show_info
  FROM dataset.meta m,
	LATERAL  (SELECT count(*) as n_rows FROM dataset.big WHERE source=m.id) t
	ORDER BY 2
;
CREATE VIEW dataset.vmeta_summary AS
  SELECT id, urn, pkey::text, lang, n_cols, n_rows
	FROM dataset.vmeta_summary_aux
;
CREATE VIEW dataset.vjmeta_summary AS
  SELECT jsonb_agg(to_jsonb(v)) AS jmeta_summary
	FROM dataset.vmeta_summary_aux v
;

CREATE VIEW dataset.vmeta_fields AS
  SELECT id, urn, f->>'name' as field_name, f->>'type' as field_type,
         f->>'description' as field_desc
  FROM (
    SELECT id, kx_urn as urn, jsonb_array_elements(info#>'{schema,fields}') as f
    FROM dataset.meta
  ) t
;
CREATE VIEW dataset.vjmeta_fields AS
  -- use SELECT jsonb_agg(jmeta_fields) as j FROM dataset.vjmeta_fields WHERE dataset_id IN (1,3);
	SELECT id AS dataset_id,
	  jsonb_build_object('dataset', dataset, 'fields', json_agg(field)) AS jmeta_fields
	FROM (
	  SELECT id,
		     jsonb_build_object('id',id, 'urn',urn) as dataset,
	       jsonb_build_object('field_name',field_name, 'field_type',field_type, 'field_desc',field_desc) as field
	  FROM dataset.vmeta_fields
	) t
	GROUP BY id, dataset
;
