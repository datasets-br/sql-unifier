# try-sql-datasets

Try all datasets in a single PostgreSQL database, plug-and-play!

All datasets load and inserted in a single big table, where each CSV line was converted into a [JSON array](https://specs.frictionlessdata.io/tabular-data-resource/#json-tabular-data). In PostgreSQL 9.5+ the best way to digital preservation is the [JSONb datatype](https://www.postgresql.org/docs/current/static/datatype-json.html), so the big table of datasets is:

```sql
CREATE TABLE dataset.big (
  id bigserial not null primary key,
  source int NOT NULL REFERENCES dataset.confs(id) ON DELETE CASCADE,
  key text,  -- optional
  c JSONb,
  UNIQUE(source,key)
);
```
Each line of all CSV files is loaded into a *JSONb array*:  CSV datatype is preserved and data representation is the most efficient and compressed &mdash; with fast access, indexation and full flexibility of [JSONb functions and operators](https://www.postgresql.org/docs/current/static/functions-json.html). 

The framework also offers usual relational data access by SQL VIEW, generated automatically (!) and casting original datatypes to consistent SQL datatypes, to build joins and other complex SQL expressions from the preserved datasets. 

## Simplest use (demo)

If there are no special database, use `trydatasets` database. If there are no special user, etc. try with `psql -h localhost -U postgres`

```sh
git clone https://github.com/datasets-br/try-sql-datasets.git
cd try-sql-datasets
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/step1-lib.sql
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/step2-strut.sql
sh src/cache/step3-1.sh
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/cache/step3-2.sql
```

Done!  Try eg. with `psql` some queries:
* a summary of all saved datasets: `SELECT * FROM dataset.vw_conf_summary;`
* a complete list of all fields:  `SELECT * FROM dataset.vw_conf_fields;`
* all brasilian states at CSV file: `SELECT * FROM tmpcsv_br_state_codes;`
* same dataset in the database as a big table of JSON arrays: `SELECT c FROM dataset.big where dataset.idconfig('br_state_codes');`
* same again, but using a SQL VIEW for `dataset.big` table: `SELECT * FROM vw_br_state_codes;`

## Configurating
 
Change the default [conf.json](conf.json) to your needs, 
pointing it to datasets of [github.com/datasets](https://github.com/datasets) or [datasets.ok.org.br](http://datasets.ok.org.br). Example: all CSVs of [country-codes](https://github.com/datasets/country-codes), of [city-codes](https://github.com/datasets-br/city-codes) and the main CSV of [state-codes](https://github.com/datasets-br/state-codes),
```json
{
   "github.com":{
        "datasets/country-codes":null,
        "datasets-br/state-codes":"br-state-codes",
        "datasets-br/city-codes":null
   },
   "useBig":true, "useIDX":false, "useRename":true
}
```
The `use*` flags are for create or not the big table *dataset.All*, nominate temporary tables by an index or with real dataset names, and, nominating fields, use or not an rename rule.

Tested with pg9.5 in a UBUNTU 16 LTS.

### Install with the new configuration

After edit `conf.json`, run the `pack2sql` and again the sequence of init commands (supposing at root of the git),

```sh
php src/php/pack2sql.php # at each conf edit 
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/step1-lib.sql # once
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/step2-strut.sql # to drop cascade
# rm -r /tmp/tmpcsv # if need to rebuild from new data in the Web
sh src/cache/step3-1.sh 
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/cache/step3-2.sql
```

## Using with SQL

All CSV lines of all CSV files was loaded in JSON arrays, at table `dataset.big`.

All loaded foregin CSV tables are named `tmpcsv_*`. List the `*` names  with `SELECT * FROM dataset.vw_confs_summary`.<br>You can drop all server interfaces by `DROP SERVER csv_files CASCADE`, without impact in the `dataset` schema.


##  Collabore

* development: the algorithm is simple, can be any language. The reference-implamentation is PHP. See `/src/_language_` folder, at [src](src).
* using: add [issues here](https://github.com/datasets-br/try-sql-datasets/issues).


