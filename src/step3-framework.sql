/**
 * Librasry of the framework. Toolkit for create, process and manipulate datasets.
 * $f$ are functions and $wrap$ are wrap methods (overloading functions).
 */


 DROP SCHEMA IF EXISTS test123 CASCADE;  -- LIXO!
 CREATE SCHEMA test123;  -- LIXO!


-- -- --
-- -- --
-- Part 1 - public handlers toolkit, for use with dataset.big selections.

/**
 * Float-Sum of a slice of columns of the table dataset.big, avoiding nulls.
 */
CREATE FUNCTION dataset.fltsum_colslice(
  p_j JSONb,   -- from dataset.big.j
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
$f$ LANGUAGE PLpgSQL IMMUTABLE;

/**
 * Bigint-Sum of a slice of columns of the table dataset.big, avoiding nulls.
 */
CREATE FUNCTION dataset.intsum_colslice(
  p_j JSONb,   -- from dataset.big.j
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
$f$ LANGUAGE PLpgSQL IMMUTABLE;


-- -- --
-- -- --
-- Part 2 - internal functions for dataset-schema structures.
-- Used in create-tables, import, export and triggers.

/**
 * Get primaryKey selectores. Input meta.info, returns array[conactPkFields,pkcols]
 */
CREATE or replace FUNCTION dataset.metaget_schema_pk(int) RETURNS text[] AS $f$
  SELECT array[
    COALESCE(', '||array_to_string(ks, E'::text||\';\'||')||'::text', ''),
    COALESCE(array_to_string(ks, ','), '')
    -- old COALESCE(array_to_string(array_agg((dic->k)::text::int + 1), ','), '')
  ] as ret
  FROM (
    SELECT  -- old array_json_dic(kx_fields) as dic,
          dataset.jget_pks(info) as ks
    FROM dataset.meta
    WHERE id=$1
  ) t;
$f$ language SQL IMMUTABLE;

/**
 * To help draw UML class diagrams with yUML syntax.
 */
CREATE or replace FUNCTION dataset.yUML_box(int) RETURNS text AS $f$
  SELECT format(
    '[%s|%s]',
    min(name),
    array_to_string( array_agg(CASE WHEN f=any(ks) THEN '-' ELSE '' END ||f||':'||t), ';' )
  )
  FROM (
    SELECT  name, dataset.jget_pks(info) as ks,
        lib.pg_varname( unnest(kx_fields) ) f,
        unnest(kx_types) t
    FROM dataset.meta
    WHERE id=$1
  ) t
$f$ language SQL IMMUTABLE;

CREATE or replace FUNCTION dataset.yUML_box(int[]) RETURNS text AS $f$
  SELECT array_to_string(array_agg(dataset.yUML_box( x )), E'\n\n')
  FROM unnest($1) t(x)
$f$ language SQL IMMUTABLE;


/**
 * Get metadata pieces and transforms it into text-array.
 * Used in cache-refresh etc. Meta.info as Datapackage.json standard.
 */
CREATE FUNCTION dataset.metaget_schema_field(
  p_info JSONb, p_field text
) RETURNS text[] AS $f$
  SELECT array_agg(x)
  FROM (  -- need to "cast" from record to table, to use array_agg
    SELECT (jsonb_array_elements($1#>'{schema,fields}')->>p_field)::text
  ) t(x)
$f$ language SQL IMMUTABLE;

CREATE FUNCTION dataset.metaget_schema_field(
  p_id int, p_field text
) RETURNS text[] AS $f$
  SELECT dataset.metaget_schema_field(info,$2)
  FROM  dataset.meta
  WHERE id=$1 --kx_urn=$1
$f$ language SQL IMMUTABLE;

CREATE FUNCTION dataset.metaget_schema_field(text, text, text DEFAULT NULL) RETURNS text[] AS $wrap$
  SELECT dataset.metaget_schema_field( dataset.meta_id($1,$3), $2 )
$wrap$ language SQL IMMUTABLE;


-- -- --
-- -- --
-- Part 4 - Export toolkit.

CREATE FUNCTION dataset.copy_to(
	p_copyselect text, -- any select command
	p_filename text, -- as output
	p_tmp boolean DEFAULT true,  -- flag to use or not automatic '/tmp' as path
	p_copytype text DEFAULT ''   -- eg. 'CSV HEADER'
) RETURNS text AS $f$
DECLARE
  q_path text;
	vwname  text;
BEGIN
	p_filename := trim(p_filename);
	q_path := CASE WHEN $3 THEN '/tmp/'||$2 ELSE $2 END;
	EXECUTE format(
		E'COPY (%s) TO %L %s',
		p_copyselect, q_path, p_copytype
	);
	RETURN format(
		'Exported %L to %L%s',
		lib.msgcut(p_copyselect,50),
		q_path,
		CASE WHEN p_copytype>'' THEN ' as '||p_copytype ELSE '' END
	);
END
$f$ language PLpgSQL;

CREATE or replace FUNCTION dataset.export_yUML_boxes(
  filename text,
  int[] DEFAULT NULL::int[]
) RETURNS text AS $f$
  SELECT CASE
    WHEN $2 IS NULL THEN
     dataset.copy_to('SELECT dataset.yUML_box(array_agg(id)) FROM dataset.meta',$1)
    ELSE
     dataset.copy_to('SELECT dataset.yUML_box(array['|| array_to_string($2,',') ||']) FROM dataset.meta',$1)
  END
$f$ language SQL IMMUTABLE;

/**
 * Export a dataset (or other "thing" as the vmeta_summary), to an output format (tipically CSV or TXT).
 */
CREATE or replace FUNCTION dataset.export_thing(
	p_dataset_id int,
	p_thing text DEFAULT '',     -- nothing = vname
	p_format text DEFAULT 'csv', -- csv, json-arrays or json-objs
	p_filename text DEFAULT NULL,  -- as output
	p_tmp boolean DEFAULT true     -- flag to use or not automatic '/tmp' as path
) RETURNS text AS $f$
DECLARE
	vname text;
	aux text;
	aux2 text;
BEGIN
	IF p_thing IS NULL THEN p_thing=''; END IF;
	vname := dataset.viewname($1);
	p_filename := trim(p_filename);
	IF p_filename IS NULL OR p_filename='' THEN
		aux := regexp_replace(vname,'^vw(\d*)','out\1');
		p_filename:= aux || '.' || CASE WHEN p_format='csv' THEN 'csv' ELSE 'json' END;
	END IF;

	IF p_format='csv' THEN
		aux := CASE WHEN p_thing='' THEN 'dataset.'||vname ELSE p_thing END;
		aux := 'SELECT * FROM ' || aux;
	ELSEIF p_format='json-arrays' THEN
		aux := CASE WHEN p_thing='' THEN 'dataset.jsonb_arrays('|| $1 ||')' ELSE p_thing END;
	  aux := 'SELECT '||aux;
	ELSE -- json-objs
		aux := CASE WHEN p_thing='' THEN 'dataset.jsonb_objects('|| $1 ||')' ELSE p_thing END;
		aux := 'SELECT '||aux;
	END IF;
	RETURN dataset.copy_to(
		aux,
		p_filename,
		p_tmp,
		CASE WHEN p_format='csv' THEN 'CSV HEADER' ELSE '' END
	);
END
$f$ language PLpgSQL;

CREATE or replace FUNCTION dataset.export_thing(
	p_urn text,  text DEFAULT '',  text DEFAULT 'csv',
	text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$
	SELECT dataset.export_thing( dataset.meta_id($1), $2, $3, $4, $5)
$wrap$ language SQL IMMUTABLE;

--- CSV:
CREATE FUNCTION dataset.export_as_csv(
	int, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'csv', $2, $3) $wrap$ language SQL IMMUTABLE;

CREATE FUNCTION dataset.export_as_csv(
	text, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'csv', $2, $3)  $wrap$ language SQL IMMUTABLE;

---- JSON ARRAYS:
CREATE FUNCTION dataset.export_as_jarrays(
	int, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'json-arrays', $2, $3)  $wrap$ language SQL IMMUTABLE;

CREATE FUNCTION dataset.export_as_jarrays(
	text, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'json-arrays', $2, $3)  $wrap$ language SQL IMMUTABLE;

---- JSON OBJCTS:
CREATE FUNCTION dataset.export_as_jobjects(
	int, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'json-objs', $2, $3)  $wrap$ language SQL IMMUTABLE;

CREATE FUNCTION dataset.export_as_jobjects(
	text, p_filename text DEFAULT NULL, boolean DEFAULT true
) RETURNS text AS $wrap$ SELECT dataset.export_thing( $1, NULL, 'json-objs', $2, $3)  $wrap$ language SQL IMMUTABLE;


CREATE or replace FUNCTION dataset.copy_to(JSONb, p_filename text, boolean DEFAULT true) RETURNS text AS $f$
-- Is a WORKAROUND, but working fine.
DECLARE
	aux text;
BEGIN
	DROP TABLE IF EXISTS tmp_json_output;
  CREATE TEMPORARY TABLE tmp_json_output(info JSONb);
	INSERT INTO tmp_json_output(info) VALUES($1);
  SELECT dataset.copy_to('SELECT info FROM tmp_json_output LIMIT 1', $2, $3) INTO aux;
	DROP TABLE tmp_json_output;
	RETURN aux;
END
$f$ language PLpgSQL;

-- -- --
-- -- --
-- Part 5 - Rename and merge toolkit.

-- Need to add also dataset.rename() and dataset.rename_ns  functions

CREATE or replace FUNCTION dataset.merge_into(
	p_from_id int,
	p_into_id int
) RETURNS text AS $f$
BEGIN
	IF (select kx_types from dataset.meta where id=$1) = (select kx_types from dataset.meta where id=$2) THEN
		UPDATE dataset.big
		SET source=p_into_id
		WHERE source=p_from_id;
		DELETE FROM dataset.meta WHERE id=p_from_id;
		RETURN 'ok';
	ELSE
		RETURN 'not same kx_types';
	END IF;
END
$f$ language PLpgSQL;

CREATE or replace FUNCTION dataset.merge_into(  int[], int ) RETURNS text AS $wrap$
	SELECT dataset.merge_into(x,$2) FROM unnest($1) t(x)
$wrap$ language SQL;

CREATE or replace FUNCTION dataset.merge_into(  text, text ) RETURNS text AS $wrap$
	SELECT dataset.merge_into(dataset.meta_id($1), dataset.meta_id($2))
$wrap$ language SQL;

CREATE or replace FUNCTION dataset.merge_into(  text[], text ) RETURNS text AS $wrap$
	SELECT dataset.merge_into(x,$2) FROM unnest($1) t(x)
$wrap$ language SQL;

/**
 * Merge two or more datasets in a new one with a new column with the dataset-id.
 */
CREATE or replace FUNCTION dataset.merge_tonew(
	-- include the dataset name as new column in the merge. Clones meta from first.
	p_ids int[],
	p_name text -- new dataset name
) RETURNS text AS $f$
DECLARE
  i int;
	first int;
	fist_types text[];
	rest int[];
	idnew int;
BEGIN
	first := p_ids[1];
	rest  := p_ids[2:array_upper(p_ids,1)];
	SELECT kx_types INTO fist_types FROM dataset.meta WHERE id=first;
	FOREACH i IN ARRAY rest LOOP
		IF fist_types != (SELECT kx_types FROM dataset.meta where id=i) THEN
			RETURN 'not same kx_types, see ids: '||first ||' and '||i;
		END IF;
	END LOOP;
	INSERT INTO dataset.meta(name,info) VALUES (p_name,(SELECT info FROM dataset.meta WHERE id=first));
	idnew := dataset.meta_id(p_name);
	-- basta fazer || [source]
	INSERT INTO dataset.big(source, j) SELECT idnew,j FROM dataset.big WHERE source = ANY($1);
	return 'criou o new!';
END
$f$ language PLpgSQL;


-- -- --
-- -- --
-- Part 6 - Build structure (create clauses) toolkit.

/**
 * Build SQL fragments for CREATE clauses.
 * @param p_dataset_id at dataset.meta
 * @return array[viewName, tabName, colItems, fieldTypeItens]
 */
CREATE or replace FUNCTION dataset.build_sql_names(p_dataset_id int) RETURNS text[] AS $f$
DECLARE
	vname text;
	tname text;
	i int;
	q_fields text[];
	q_types  text[];
	c_item   text[];
	flditem  text[];
	sqltype  text;
BEGIN
	vname := 'dataset.'||dataset.viewname($1);
	tname := dataset.viewname($1,true);
	SELECT lib.pg_varname(kx_fields), kx_types
	  INTO q_fields,                  q_types
	FROM dataset.meta WHERE id=$1;
	IF q_types IS NULL OR q_fields IS NULL THEN
		RAISE EXCEPTION 'internal4 - No cache for view generation';
	END IF;
	FOR i IN 1..array_upper(q_fields,1) LOOP
		sqltype := lib.jtype_to_sql(q_types[i]);
		c_item[i] := ' (j->>'|| (i-1) || ')::'|| sqltype ||' AS '|| q_fields[i];
		flditem[i] := q_fields[i] ||' '|| sqltype;
	END LOOP;
	RETURN array[vname, tname, array_to_string(c_item,', '), array_to_string(flditem,', '), array_to_string(q_fields,', ')];
END
$f$ language PLpgSQL;

/**
 * EXECUTE SQL clauses for drop/create VIEWs and FOREIGN TABLEs.
 * @param p_dataset_id at dataset.meta
 * @return array[viewName, dropView, createView, FgnName, dropFgnTab, viewFgnTab]
 */
CREATE or replace FUNCTION dataset.create(
	p_dataset_id int,
	p_filename text DEFAULT '',
	p_useHeader boolean DEFAULT true,
	p_delimiter text DEFAULT ',',
	p_intoSelect text DEFAULT ''  -- add do-flags array for each execute (1..5).
) RETURNS text AS $f$
DECLARE
  p text[];
  pk text[];
	i int;
	s text;
BEGIN
	p := dataset.build_sql_names($1); -- p1=vname, p2=tname, p3=c_itens, p4=tab_itens, P5=field_names
	FOR i IN 1..2 LOOP  IF relname_exists(p[i]) THEN  -- p[i]>'' AND
			s := CASE WHEN i=1 THEN 'VIEW' ELSE 'FOREIGN TABLE' END;
			EXECUTE format('DROP %s %s CASCADE;', s, p[i]);
	END IF; END LOOP;

  s:= format(
		'SELECT %s FROM (SELECT jsonb_array_elements(j) FROM dataset.big WHERE source=%s) t(j)',
    p[3], $1
	);
  pk := dataset.metaget_schema_pk($1); -- 1=conactPkFields,2=pkcols
	EXECUTE format(
		'CREATE VIEW %s AS %s',
    p[1], CASE WHEN pk[1]>'' THEN 'SELECT * FROM ('||s||') t2 ORDER BY '||pk[2] ELSE s END
	);

	IF p_delimiter='' OR p_delimiter IS NULL THEN p_delimiter=','; END IF;
	EXECUTE format(
		'CREATE FOREIGN TABLE %s (%s) SERVER csv_files OPTIONS (filename %L, format %L, delimiter %L, header %L)',
		 p[2],  p[4], p_filename, 'csv', p_delimiter, p_useHeader::text
	);

	IF p_intoSelect='' OR p_intoSelect IS NULL THEN
    --no key s:= CASE WHEN pk[1]='' THEN '' ELSE 'ORDER BY '||pk[2] END;
		p_intoSelect := format(
			'SELECT %s, jsonb_agg(jsonb_build_array(%s)) FROM %s',
			-- no key $1, pk[1], p[5], p[2], s
      $1, p[5], p[2]
    );
	END IF;
	-- no key s:= CASE WHEN pk[1]='' THEN '' ELSE ',key' END;
	EXECUTE format( 'INSERT INTO dataset.big(source,j)  %s', p_intoSelect );

	RETURN format('ok all created for %s (id %s)', p[1], $1);
END
$f$ language PLpgSQL;

CREATE or replace FUNCTION dataset.create(
	p_urn text, text DEFAULT '', boolean DEFAULT true, text DEFAULT ',', text  DEFAULT ''
) RETURNS text AS $wrap$
	SELECT dataset.create( dataset.meta_id($1), $2, $3, $4, $5 )
$wrap$ language SQL IMMUTABLE;

-- -- --
-- -- --
-- Part 7 - Import toolkit.

-- .. later



-- -- --
-- -- --
-- Part 8 - Basic and automatic assertions.

-- Eg. check uniqueness of declared primaryKeys  ...

CREATE or replace FUNCTION dataset.validate(int DEFAULT NULL) RETURNS JSONb AS $f$
DECLARE
    dst RECORD;
    jj JSONb;
    q_id int;
    q_assert boolean;
BEGIN
  FOR dst IN SELECT * FROM dataset.meta WHERE (CASE WHEN $1 IS NOT NULL THEN id=$1 ELSE true END) LOOP
    q_id := dst.id;
    RAISE NOTICE 'Checking errors for % ... (no message is success)', quote_ident(dst.kx_urn);
    CASE dst.jtd
      WHEN 'tab-aoa' THEN
        SELECT j INTO jj FROM dataset.big WHERE source=q_id;
        IF NOT (jsonb_array_length(jj)>0) THEN
          RAISE NOTICE 'ERROR 1a: first-level array empty';
        ELSEIF NOT (jsonb_array_length(jj->0)>0) THEN
          RAISE NOTICE 'ERROR 2a: second-level array empty';
        END IF;
      WHEN 'tab-aoo' THEN
        SELECT j INTO jj FROM dataset.big WHERE source=q_id;
        IF NOT (jsonb_array_length(jj)>0) THEN
          RAISE NOTICE 'ERROR 1b: first-level array empty';
        ELSEIF NOT (jsonb_array_length(jj->0)>0) THEN
          RAISE NOTICE 'ERROR 2b: second-level array empty';
          END IF;
      ELSE
        RAISE NOTICE 'ERROR33: not developed asserts for %', quote_ident(dst.jtd);
    END CASE; -- dst.jtd
  END LOOP;
END
$f$ language PLpgSQL;
