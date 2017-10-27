# SQL dataset unifier

Try all datasets in a single PostgreSQL database, plug-and-play! Load and manage all your [FrictionLessData tabular packages](http://specs.frictionlessdata.io/tabular-data-package/) (CSV datasets).

Load in a single big table, where each CSV line is converted into a [JSON array](https://specs.frictionlessdata.io/tabular-data-resource/#json-tabular-data).
In PostgreSQL 9.5+ the best way to digital preservation is the [JSONb datatype](https://www.postgresql.org/docs/current/static/datatype-json.html), so the big table of datasets is:

```sql
CREATE TABLE dataset.big (
  id bigserial not null primary key,
  source int NOT NULL REFERENCES dataset.meta(id) ON DELETE CASCADE, -- Dataset ID and metadata.
  key text,  -- Dataset primary key (converted to text) is optional.
  c JSONb CHECK(jsonb_array_length(c)>0), -- all dataset columns here, as exact copy of CSV line!
  UNIQUE(source,key)
);
```

Each line of all CSV files is loaded into a *JSONb array*:  CSV datatype is preserved and data representation is the most efficient and compressed &mdash; with fast access, indexation and full flexibility of [JSONb functions and operators](https://www.postgresql.org/docs/current/static/functions-json.html).

The framework also offers usual relational data access by SQL VIEW, generated automatically (!) and casting original datatypes to consistent SQL datatypes, to build joins and other complex SQL expressions from the preserved datasets.

## Simplest use (demo)

If there are no special database, create `trydatasets` database. If there are no special user, etc. you can use the URI-connection `postgresql://postgres:postgres@localhost/trydatasets` as at default [conf.json](conf.json).

```sh
git clone https://github.com/datasets-br/try-sql-datasets.git
cd try-sql-datasets
php src/php/pack2sql.php # generates cache from default conf.json
sh src/cache/make.sh
```

Done!  Try eg. with `psql URI` (as connection comment above) some queries:
* a summary of all saved datasets: `SELECT * FROM dataset.vw_meta_summary;`
* a complete list of all fields:  `SELECT * FROM dataset.vw_meta_fields;`
* all brasilian states at CSV file: `SELECT * FROM tmpcsv_br_state_codes;`
* same dataset in the database as a big table of JSON arrays: `SELECT c FROM dataset.big where dataset.idconfig('br_state_codes');`
* same again, but using a SQL VIEW for `dataset.big` table: `SELECT * FROM vw_br_state_codes;`

Minimal installation:

* PostgreSQL v9.6+
* (optional) [CSVkit](csvkit.readthedocs.io)

All tested with pg9.6 in a UBUNTU 16 LTS.

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
   "useBig":true, "useIDX":false, "useRename":true
}
```

The `use*` flags are for create or not the big table *dataset.Big*; for nominate temporary tables by an index or with real dataset names; and, for nominate fields, using or not an rename rule (to avoid quotes in SQL commands).

To use local folder instead Github repository, add the path as `local`. When there are no `datapackage.json` descriptor in the folder, use `local-csv` to point each CSV file. For instance:
```json
"github.com":{ "...":"..." },
"local":{"/home/user/sandbox/cbh-codes":null},
"local-csv":["../test123.csv"],
```

After edit `conf.json`, run the `pack2sql` and again the sequence of init commands (supposing at root of the git),

```sh
php src/php/pack2sql.php # at each conf edit
rm -r /tmp/tmpcsv        # only when need to rebuild from new data in the Web
sh src/cache/make.sh     # rebuilds CSV files by wget and rebuilds SQL
```

## Using with SQL and _useBig_

All CSV lines of all CSV files was loaded in JSON arrays, at table `dataset.big`.

All loaded foregin CSV tables are named `tmpcsv_*`. List the `*` names  with `SELECT * FROM dataset.vw_meta_summary`.<br>You can drop all server interfaces by `DROP SERVER csv_files CASCADE`, without impact in the `dataset` schema.

To generate full *`dataset` schema* for an external database (to avoid to read CSV or local FOREGIN TABLE), try something like `pg_dump -n dataset postgresql://postgres:postgres@localhost:5432/trydatasets > /tmp/dump_n_dataset.sql`.

### Only shell and SQL
There are no external library or language dependences. Only the *script generator* is a language-dependent module (eg. [PHP script](src/php)), all installation scripts are language-agnostic: see  [src/*.sql](src) and [src/cache](src/cache), you need only shell and `psql` (or a SQL-migration tool) to create the `dataset` SQL schema with the configurated datasets.

##  Collabore

* development: the algorithm is simple, can be any language. The reference-implamentation is PHP. See `/src/_language_` folder, at [src](src).
* using: add [issues here](https://github.com/datasets-br/try-sql-datasets/issues).
