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

To create a new `src/cache/make.sh` afer edit [conf.json](../conf.json) use

```sh
php src/php/pack2sql.php
sh src/cache/make.sh
```

after edit *conj.json*.

-----

## The dataset.big structure

The `dataset.big` and `dataset.meta` tables are defined in the [`step2-strut.sql`](step2-strut.sql) file as below:
```sql
CREATE TABLE dataset.meta (
	id serial PRIMARY KEY,
	tmp_name text,
	kx_fields text[],
	kx_types text[],
	info JSONb
);
CREATE TABLE dataset.big (
  id bigserial not null primary key,
  source int NOT NULL REFERENCES dataset.meta(id) ON DELETE CASCADE, -- Dataset ID and metadata.
  key text,  -- Optional. Dataset primary key (converted to text).
  c JSONb CHECK(jsonb_array_length(c)>0), -- All dataset columns here, as exact copy of CSV line!
  UNIQUE(source,key)
);
```
it is builded into the database when you run `make.sh`.

## The generated code

When running the generator (eg. by `php src/php/pack2sql.php`) you will crete two files in the `/src/cache` folder, the `make.sh` and `step3-buildDatasets.sql`. The last is the main and a standard  SQL script.

Lets use the [language-codes.csv](https://github.com/datasets/language-codes/blob/master/data/language-codes.csv) example, that is configured by the demo's *conf.json*, is a dataset of *language-codes*. The dataset importer of its structure is

```sql
CREATE FOREIGN TABLE tmpcsv_language_codes (
 alpha2 text,
 english text
 ) SERVER csv_files OPTIONS (
    filename '/tmp/tmpcsv/language_codes.csv',
    format 'csv',
    header 'true'
 );
```
You can use only it, while the `/tmp/tmpcsv/language_codes.csv` file is there (the `make.sh` generates it), as "no table", is a direct CSV reader.

But if you want to preserve it in the database, you'll like to transfer it to the `dataset.big` table, and all informations of the original [datapackage.json](https://github.com/datasets/language-codes/blob/master/datapackage.json) to the `dataset.meta` table. So the gerator do it for you:

```sql
INSERT INTO dataset.meta(tmp_name,info) VALUES
 ('language_codes','{"name":"language-codes","path":"data/language-codes.csv","mediaty
pe":"text/csv","schema":{"fields":[{"name":"alpha2","description":"2 letter alpha-2 code","type":"string"},{"name":"English","description":"Eng
lish name of language","type":"string"}]}}'::jsonb)
;

INSERT INTO dataset.big(source, c)
  SELECT dataset.idconfig('language_codes') , jsonb_build_array( alpha2, english   )
  FROM tmpcsv_language_codes
;

UPDATE dataset.meta
SET  kx_fields=dataset.metaget_schema_field(info,'name'),
     kx_types=dataset.metaget_schema_field(info,'type')
;
```

To simplify the access to the dataset via usual `SELECT` SQL clause, the generator also create a VIEW, translating each field name and datatype to the most adequate to PostgreSQL:

```sql
CREATE VIEW dataset.vw_language_codes AS
  SELECT (c->>0)::text AS alpha2, (c->>1)::text AS english
  FROM dataset.big where source=dataset.idconfig('language_codes') ORDER BY id;
```

As this isertions and VIEW creations was doed, you can DROP the `tmpcsv_language_codes` FOREIGN TABLE, because you have an exact copy of it into the `dataset.big` table, named `language_codes` (source-ID `1`) and with a view `dataset.vw_language_codes`. To drop all foregin tables use `DROP SERVER csv_files CASCADE` (and to remove from '/tmp' use `rm -r /tmp/tmpcsv`).

------

# APPENDIX

Reproducing some *demo* results.

`SELECT * FROM dataset.vmeta_summary`

id |      tmp_name       |               pkey               | lang | n_fields
---|---------------------|----------------------------------|------|----------
 1 | language_codes      |                                  |      |        2
 2 | language_codes_3b2  |                                  |      |        3
 3 | language_codes_full |                                  |      |        5
 4 | ietf_language_tags  |                                  |      |        7
 5 | country_codes       |                                  |      |       56
 6 | br_state_codes      | "id"                             | en   |       15
 7 | br_city_synonyms    | ["state", "lexLabel", "synonym"] | pt   |        5
 8 | br_city_codes       | ["state", "lexLabel"]            | pt   |        9

----

`SELECT * FROM dataset.vmeta_fields`

id |      tmp_name       |         field_name    | field_type |      field_desc
---|---------------------|-----------------------|------------|-------------------
1 | language_codes      | alpha2                | string     | 2 letter alpha-2 code
1 | language_codes      | English                                 | string     | English name of language
2 | language_codes_3b2  | alpha3-b                                | string     | 3 letter alpha-3 bibliographic code
2 | language_codes_3b2  | alpha2                                  | string     | 2 letter alpha-2 code
2 | language_codes_3b2  | English                                 | string     | English name of language
3 | language_codes_full | alpha3-b                                | string     | 3 letter alpha-3 bibliographic code
3 | language_codes_full | alpha3-t                                | string     | 3 letter alpha-3 terminologic code (when given)
3 | language_codes_full | alpha2                                  | string     | 2 letter alpha-2 code (when given)
... |      ...       |         ...    | ... |      ...
8 | br_city_codes       | creation                                | integer    | State official creation year
8 | br_city_codes       | extinction                              | integer    | State official creation year (null for in use)
8 | br_city_codes       | postalCode_ranges                       | string     | Numeric ranges of postal codes
8 | br_city_codes       | notes                                   | string     | Notes about assegments, dates or changes

----

```sql
SELECT jsonb_pretty(jsonb_agg(jmeta_fields))
FROM dataset.vjmeta_fields WHERE dataset_id IN (1,3)
```

```json
[
    {
      "dataset": {
          "id": 1,
          "tmp_name": "language_codes"
      },      
      "fields": [
          {
              "field_desc": "2 letter alpha-2 code",
              "field_name": "alpha2",
              "field_type": "string"
          },
          {
              "field_desc": "English name of language",
              "field_name": "English",
              "field_type": "string"
          }
        ]
    },
    { "datasets": "...", "fields": "..."}
]
```

----

```sql
SELECT i.lang, i.defs, substring(l.english,1,30) as lang_name, c.official_name_en as contry_name
FROM dataset.vw_ietf_language_tags i INNER JOIN dataset.vw_country_codes c
  ON c.iso3166_1_alpha_2=i.territory INNER JOIN dataset.vw_language_codes l
  ON i.langtype=l.alpha2
ORDER BY 1;
```

lang           | defs |           lang_name          |   contry_name
---------------|------|------------------------------|-----------------
af-NA          |    2 | Afrikaans                    | Namibia
af-ZA          |    0 | Afrikaans                      | South Africa
ak-GH          |    0 | Akan                           | Ghana
am-ET          |    0 | Amharic                        | Ethiopia
ar-AE          |    3 | Arabic                         | United Arab Emirates
ar-BH          |    0 | Arabic                         | Bahrain
ar-DJ          |    1 | Arabic                         | Djibouti
ar-DZ          |    2 | Arabic                         | Algeria
ar-EG          |    1 | Arabic                         | Egypt
...           | ... |           ...          |   ...
hi-IN          |    0 | Hindi                          | India
hr-BA          |    2 | Croatian                       | Bosnia and Herzegovina
hr-HR          |    0 | Croatian                       | Croatia
hu-HU          |    0 | Hungarian                      | Hungary
hy-AM          |    0 | Armenian                       | Armenia
id-ID          |    0 | Indonesian                     | Indonesia
ig-NG          |    0 | Igbo                           | Nigeria
ii-CN          |    0 | Sichuan Yi; Nuosu              | China
is-IS          |    0 | Icelandic                      | Iceland
it-CH          |    3 | Italian                        | Switzerland
it-IT          |    0 | Italian                        | Italy
it-SM          |    0 | Italian                        | San Marino
it-VA          |    0 | Italian                        | Holy See
ja-JP          |    0 | Japanese                       | Japan
...           | ... |           ...          |   ...
zh-Hant-HK     |    8 | Chinese                        | China, Hong Kong Sp. Adm. Reg.
zh-Hant-MO     |    1 | Chinese                        | China, Macao Sp. Adm. Reg.
zh-Hant-TW     |    0 | Chinese                        |
zu-ZA          |    0 | Zulu                           | South Africa

## See datasets as diagrams

Conventions with [yUML](https://yuml.me):

```
[MyDataset1|-pk_field1:int;field2:int;field3:string;field4:array]
[MyDataset2|-pk1_field:string;field2:int;field3:object|field2-MyDataset1(pk_field1)]

[MyDataset1]0..1---*[MyDataset2]
```
![](https://yuml.me/7ba8f15f.png)

So the our [conf.json](../conf.json) can offer also initial `[datasetName|-pk_field1:type;field2:type;...]` definitions to use with it. Set the `useYUml` flag to *true*.

Example of handicraft diagram builded from automatic source-code of definitions.

```
// Script generated by datapackage.json files and pack2sql generator.
// Created in 2017-11-05

// (original changed to add PKs and FK-references)

[country-codes|official_name_en:string;-iso3166_1_alpha_2:string; iso3166_1_alpha_3:string; iso3166_1_numeric:string; is_independent:string]

[ietf-language-tags|-lang:string;langtype:string;territory:string;revgendate:string;defs:integer;dftlang:boolean;file:string|ref-territory-country_codes(iso3166_1_alpha_2)]

[br-state-codes|-subdivision:string;name_prefix:string;name:string;id:integer;wdid:string|refConstant-country_codes(iso3166_1_alpha_2)]

[br-city-codes|-name:string;-state:string;wdid:string;idibge:string|ref-state-country_codes(subdivision)]

// Relationships are handicrafted
[country-codes]1---*[ietf-language-tags]
[country-codes]BR---*[br-state-codes]
[br-state-codes]1---1..*[br-city-codes]
```

![](https://yuml.me/8c3784c5.png)
