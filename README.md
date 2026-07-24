# mysql-to-sqlite

A standalone, schema-aware copier extracted from Invoicer. It copies raw table data
from MySQL to an existing SQLite database through Active Record, without loading an
application's models or running callbacks.

The source and destination must have matching table columns and the same maximum
`schema_migrations.version`. The importer refuses a non-empty destination by default,
copies in batches, and validates row counts, foreign keys, and integer sequences.

## Install

```sh
bundle install
```

The MySQL client development library must be available when Bundler installs `mysql2`.

## Use

First create or migrate an empty SQLite database to exactly the schema version recorded
in MySQL. Then run:

```sh
bundle exec bin/mysql-to-sqlite \
  --source 'mysql2://user:password@127.0.0.1/database' \
  --destination /absolute/path/to/database.sqlite3 \
  --yes
```

The URLs may instead be supplied as `MYSQL_SOURCE_URL` and
`SQLITE_DATABASE_PATH`. Run `bundle exec bin/mysql-to-sqlite --help` for all options.

`--replace` deletes records from matching destination tables before copying.
`--ignore-source-only` skips tables found only in MySQL; use it only after inspecting
why the schemas differ.

Stop all writes during the final import and keep verified backups. This tool copies
database records only; application uploads and encryption keys must be preserved
separately.
