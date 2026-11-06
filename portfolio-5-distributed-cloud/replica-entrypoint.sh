#!/bin/bash
# Waits for the primary, copies it with pg_basebackup (-R makes it a standby), then starts it read-only.
set -e
until pg_isready -h pg-primary -U farpoint -d farpoint; do sleep 3; done
sleep 10    # let the primary finish loading the seed data
if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  rm -rf /var/lib/postgresql/data/*
  pg_basebackup -h pg-primary -U replicator -D /var/lib/postgresql/data -R -X stream -P
  chown -R postgres:postgres /var/lib/postgresql/data && chmod 700 /var/lib/postgresql/data
fi
exec gosu postgres postgres -c hot_standby=on
