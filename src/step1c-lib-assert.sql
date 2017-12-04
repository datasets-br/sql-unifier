
-------------------
-------------------
-------------------
--- ASSERT REPORT toolkit

-- Main: assert_add() in the assert-procedure, and assert_show() for user report.

/**
 * Add item to an assert list.
 */
CREATE or replace FUNCTION lib.assert_g_add(
  assert_cmp boolean,         -- 1. The ASSERT CONDICTION
  code numeric,               -- 2. Code or assert-number in a sequence of asserts.
  list JSONb DEFAULT NULL,    -- 3. Note: only first of list can be null!
  group text DEFAULT 'main',      -- 4. Name of the assert-group.
  message_fail text DEFAULT NULL, -- 5. Recommended on-fail-message.
  is_warning DEFAULT false,       -- 6. Note: advertência ou erro de fato
  message text DEFAULT NULL       -- 7. Flag to "use afirmative message" and the message itself.
) RETURNS JSONb AS $f$
  SELECT COALESCE(list,'[]'::JSONb) || jsonb_build_array(CASE
    WHEN assert_cmp AND message IS NOT NULL THEN
      jsonb_build_object('code',code, 'status','SUCCESS', 'message',message)
    WHEN assert_cmp THEN   jsonb_build_object('code',code, 'status','SUCCESS')
    ELSE jsonb_build_object('code',code, 'status', CASE WHEN COALESCE(is_warning,false) THEN 'WARNING' ELSE 'ERROR' END, 'message',message_fail)
  END)
$f$ language SQL IMMUTABLE;

-- -- --
CREATE or replace FUNCTION lib.assert_add(  -- all minus group
  assert_cmp boolean, code numeric, list JSONb DEFAULT NULL,
  message_fail text DEFAULT NULL, is_warning DEFAULT false, message text DEFAULT NULL
) RETURNS JSONb AS $wrap$
  SELECT lib.assert_g_add($1, $2, $3,'main', message_fail, is_warning, message)
$wrap$ language SQL IMMUTABLE;

CREATE or replace FUNCTION lib.assert_add(JSONb,JSONb DEFAULT NULL) RETURNS JSONb AS $wrap$
  SELECT lib.assert_g_add(
    $1->>'result',($1->>'code')::numeric, $2, COALESCE($1->>'group','main'),
    $1->>'message_fail', $1->>'is_warning', $1->>'message'
  )
$wrap$ language SQL IMMUTABLE;

-- -- --

CREATE or replace FUNCTION lib.assert_expand(
  list JSONb,
  show_all boolean DEFAULT false
)  RETURNS JSONb[] AS $f$
  SELECT array_agg(j)
  FROM jsonb_array_elements($1) t(j)
  WHERE show_all OR upper(j->>'status') != 'SUCCESS'
$f$ language SQL IMMUTABLE;

CREATE or replace FUNCTION lib.assert_expand_to_table(
  list JSONb,
  show_all boolean DEFAULT false
)  RETURNS TABLE (group text, status text, code numeric, message text, data JSONb) AS $f$
  SELECT j->>'group' as group, j->>'status' as satus, j->>'code' as code,
         COALESCE(j->>'message','') as message, j->'data' as data
  FROM unnest(lib.assert_expand($1,$2)) t(j)
$f$ language SQL IMMUTABLE;

/**
 * Text report.
 */
CREATE or replace FUNCTION lib.assert_show(
  p_list JSONb,
  p_show_all boolean,
  p_sep text DEFAULT E'\n',
  p_tpl text DEFAULT '* %s of %s: %s - %s.'
)  RETURNS text AS $f$
  SELECT array_to_string(array_agg(line), p_sep)
  FROM (
    SELECT format(p_tpl, code, group, status, message) as line
    FROM lib.assert_expand_to_table(p_list,p_show_all) a
  ) t
$f$ language SQL IMMUTABLE;