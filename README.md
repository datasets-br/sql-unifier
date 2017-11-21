# SQL dataset unifier

Try all datasets in a single PostgreSQL table, plug-and-play! Load and manage all your [FrictionLessData tabular packages](http://specs.frictionlessdata.io/tabular-data-package/) (CSV datasets) with SQL.

Load in a single big table, where each CSV line is converted into a [tabular JSON array](https://specs.frictionlessdata.io/tabular-data-resource/#json-tabular-data).
In PostgreSQL 9.5+ the best way to digital preservation is the [JSONb datatype](https://www.postgresql.org/docs/current/static/datatype-json.html), so the big table of datasets is:

```sql
CREATE TABLE dataset.big (
  id bigserial not null primary key,  -- control for (rare) splitted datasets
  source int NOT NULL REFERENCES dataset.meta(id) ON DELETE CASCADE, -- Controls and all metadata.
  j JSONb NOT NULL, -- Dataset contents goes here!
);
```

Each line of all CSV files is loaded into a *JSONb array*:  CSV datatype is preserved and data representation is the most efficient and compressed &mdash; with fast access, indexation and full flexibility of [JSONb functions and operators](https://www.postgresql.org/docs/current/static/functions-json.html). The most important to manage lines of tabular data is to split by *jsonb_array_elements()* function or to join by *jsonb_agg()* function (see [disk-usage and performance benchmarks](https://github.com/datasets-br/sql-unifier/wiki/Benchmarking)).

[The framework](https://github.com/datasets-br/sql-unifier/wiki/5.-The-framework-architecture) also offers usual relational data access by SQL-VIEW, generated automatically (!) and casting original datatypes to consistent SQL datatypes, to build joins and other complex SQL expressions from the preserved datasets. Export and import, many formats, also easy.

## Simplest use (demo)

If there are no special database, create `trydatasets` database. If there are no special user, etc. you can use the URI-connection `postgresql://postgres:postgres@localhost/trydatasets` as at default [conf.json](conf.json).

```sh
git clone https://github.com/datasets-br/try-sql-datasets.git
cd try-sql-datasets
php src/php/pack2sql.php # generates cache from default conf.json
sh src/cache/make.sh
```

Done!  Try eg. with `psql URI` (as connection comment above) some queries:
* a summary of all saved datasets: `SELECT * FROM dataset.vmeta_summary;`
* a complete list of all fields:  `SELECT * FROM dataset.vmeta_fields;`
* all brasilian states at CSV file: `SELECT * FROM tmpcsv4_br_state_codes;`
* same dataset in the database as a big table of JSON arrays: `SELECT c FROM dataset.big WHERE dataset.meta_id('br_state_codes');`
* same again, but using the standard SQL VIEW create for simplify `dataset.big` access: `SELECT * FROM vw_br_state_codes;`

For `v*meta_*` summary functions see also [Appendix](src/README.md#appendix) with JSON output and other examples.

For handling datasets in complex queries, a typical JOIN with two datasets:  [ietf_language_tags](https://github.com/datasets/language-codes/blob/master/data/ietf-language-tags.csv) and [country_codes](https://github.com/datasets/country-codes/blob/master/data/country-codes.csv),

```sql
SELECT i.*, c.official_name_en
FROM dataset.vw_ietf_language_tags i INNER JOIN dataset.vw_country_codes c
  ON c.iso3166_1_alpha_2=i.territory;
```

All tested with PostgreSQL v9.6 in an UBUNTU 16 LTS. [CSVkit](http://csvkit.readthedocs.io) v1.0.2.

## Configurating

Change the default [conf.json](conf.json) to your needs,
pointing it to datasets of [github.com/datasets](https://github.com/datasets) or [datasets.ok.org.br](http://datasets.ok.org.br). Example: all CSVs of [country-codes](https://github.com/datasets/country-codes), of [city-codes](https://github.com/datasets-br/city-codes) and the main CSV of [state-codes](https://github.com/datasets-br/state-codes),
```json
{
   "db":"postgresql://postgres:postgres@localhost:5432/trydatasets",
   "github.com":{
        "datasets/country-codes":null,
        "datasets-br/state-codes":"br-state-codes",
        "datasets-br/city-codes":null
   },
   "local-csv":{
     "test2017":{
       "separator":";",
       "folder":"/home/user/mytests"
     },
     "otherTests":"/home/user/myOthertests"
   },
   "useBig":true, "useIDX":false, "useRename":true
}
```

The `use*` flags are for create or not the big table *dataset.Big*; for nominate temporary tables by an index or with real dataset names; and, for nominate fields, using or not an rename rule (to avoid quotes in SQL commands).

To use local folder instead Github repository, add the path as `local`. For instance:

```json
"github.com":{ "...":"..." },
"local":{"/home/user/sandbox/cbh-codes":null},
```
When there are no `datapackage.json` descriptor in the folder, use `local-csv` as the example above (JSON with `folder` and `separator` fields). You can also to point each CSV file directly, example: `"local-csv":["../test12.csv", "/tmp/t.csv"]`.

After edit `conf.json`, run the `pack2sql` and again the sequence of init commands (supposing at root of the git),

```sh
php src/php/pack2sql.php # at each conf edit
rm -r /tmp/tmpcsv        # only when need to rebuild from new data in the Web
sh src/cache/make.sh     # rebuilds CSV files by wget and rebuilds SQL
```

## Using with SQL and _useBig_

All CSV lines of all CSV files was loaded in JSON arrays, at table `dataset.big`.

All loaded foregin CSV tables are named `tmpcsv_*`. List the `*` names  with `SELECT * FROM dataset.vmeta_summary`.<br>You can drop all server interfaces by `DROP SERVER csv_files CASCADE`, without impact in the `dataset` schema.

To generate full *`dataset` schema* for an external database (to avoid to read CSV or local FOREGIN TABLE), try something like `pg_dump -n dataset postgresql://postgres:postgres@localhost:5432/trydatasets > /tmp/dump_n_dataset.sql`.

### Only shell and SQL
There are no external library or language dependences. Only the *script generator* is a language-dependent module (eg. [PHP script](src/php)), all installation scripts are language-agnostic: see  [src/*.sql](src) and [src/cache](src/cache), you need only shell and `psql` (or a SQL-migration tool) to create the `dataset` SQL schema with the configurated datasets.

## Exporting you datasets as CSV or JSON
The original datasets and your new (SQL-builded) datasets can be exported in many formats, main ones are CSV and JSON.

Lets use summarizations (`dataset.vmeta_summary` and `dataset.vmeta_fields`) as example for CSV and JSON outputs.

### SQL COPY TO

The easyest way is to export to `/tmp/` folder by `COPY t TO '/tmp/test.csv' CSV HEADER` usual command. As all `dataset.big` fragments are SQL-VIEWs, we need to express it by a SELECT. For JSON is the same, need only to ommit the `CSV` option:

```sql
-- export vmeta_summary as CSV:
 COPY (SELECT * FROM dataset.vmeta_summary) TO '/tmp/meta_summary.csv' CSV HEADER;
-- export same content as JSON-array:
 COPY (SELECT * FROM dataset.vjmeta_summary) TO '/tmp/meta_summary.json';

-- export all structured vmeta_fields as JSON-array:
 COPY (SELECT jsonb_agg(jmeta_fields) FROM dataset.vjmeta_fields) TO '/tmp/meta_fields.json';
```

To pretty-JSON you need some workaround after export `SELECT jsonb_pretty(x)`, because the lines are encoded by explicit "`\n`"...

1.   COPY fragment that you want. Eg. `COPY (SELECT jsonb_pretty(jsonb_agg(jmeta_fields)) FROM dataset.vjmeta_fields WHERE dataset_id IN (1,3)) TO '/tmp/meta_fields_1and3.json'`

2.  Convert the `\n` to real line-breaks, by `sed 's/\\n/\n/g' < /tmp/meta_fields_1and3.json > myFields.json`

### psql

With the `psql` command you can explore powerful terminal commands, to avoid `/tmp` intermediary folder (use relative path!) or use in *pipe* to remote database or remote files, *gzip*, etc.

```sh
psql -h remotehost -d remote_mydb -U myuser -c " \
   COPY (SELECT * FROM dataset.vjmeta_summary) TO STDOUT \
   " > ./relative_path/file.json
```

Internal `psql`  commands (as `\t \a \o`) are also easy, see [this tips](https://dba.stackexchange.com/a/160311/90651).


##  Collabore

* development: the algorithm is simple, can be any language. The reference-implamentation is PHP. See `/src/_language_` folder, at [src](src).
* using: add [issues here](https://github.com/datasets-br/try-sql-datasets/issues).

Other motivations: a comment about non-SQL tools like CSVkit, in its documentation, [csvkit sec.3](http://csvkit.readthedocs.io/en/1.0.2/tutorial/3_power_tools.html#csvsql-and-sql2csv-ultimate-power),

> "Sometimes (almost always), the command-line isn’t enough. It would be crazy to try to do all your analysis using command-line tools. Often times, the correct tool for data analysis is SQL".
