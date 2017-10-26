## Preparation

The database as in connection string of the default `conf.json` field `db`,  `postgresql://postgres:postgres@localhost:5432/trydatasets` is `trydatasets`...
Or change `conf.json` to your needs, the URI-template syntax is `postgresql://{user}:{password}@{host}:{port}/{dbName}`, ommiting *user*, *password*, *port* or *dbName* if your ENV is supplying it.  

To create a *pt-BR* database, connect `psql` with no database and run the script:

```sh
psql postgresql://postgres:postgres@localhost
CREATE DATABASE trydatasets
   WITH OWNER = postgres
        ENCODING = 'UTF8'
        TABLESPACE = pg_default
        LC_COLLATE = 'pt_BR.UTF-8'
        LC_CTYPE = 'pt_BR.UTF-8'
        CONNECTION LIMIT = -1
        TEMPLATE template0;
\q
```

The project is supposing standard PostgreSQL v9.5+. To create a new `src/cache/make.sh` use

```sh
php src/php/pack2sql.php
sh src/cache/make.sh
```

after edit *conj.json*.
