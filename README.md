# try-sql-datasets
Try all datasets in a single PostgreSQL database, plug-and-play!


## Installers
Change the default [conf.json](conf.json) to your needs, 
pointing it to a dataset of [github.com/datasets](https://github.com/datasets) or [datasets.ok.org.br](http://datasets.ok.org.br).

The algorithm is simple, can be any language. The reference-implamentation is PHP. See `/src/_language_` folder, at [src](src).

Tested with pg9.5 in a UBUNTU 16 LTS.

## Install with new config

Supposing you cloned the git to your local filesystem,

```sh
git clone https://github.com/datasets-br/try-sql-datasets.git
cd try-sql-datasets
# nano conf.json
```

If there are no special database, use `trydatasets` database. Create it with

```sh
PGPASSWORD=postgres psql -h localhost -U postgres
CREATE DATABASE trydatasets;
\q
```

Them, run this sequence of commands (supposing at root of the git),

```sh
php src/php/pack2sql.php
sh src/cache/makeTmp.sh
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/cache/makeTmp.sql
PGPASSWORD=postgres psql -h localhost -U postgres trydatasets < src/step1-lib.sql
```

## Install with defaults

...

## Using with SQL

All foregin CSV tables are named `tmpcsv_*`. List the `*` names  with `SELECT id,tmp_name FROM dataset.confs`.

All CSV is in JSON array, at table `dataset.all`.



