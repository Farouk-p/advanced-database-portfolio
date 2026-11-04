#!/bin/bash
# Clone the primary with pg_basebackup (-R writes standby.signal + primary_conninfo), then run as a hot standby.
set -e
until pg_isready -h pg-primary -U naija -d naijamart; do sleep 2; done
sleep 5
if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  rm -rf /var/lib/postgresql/data/*
  pg_basebackup -h pg-primary -U replicator -D /var/lib/postgresql/data -R -X stream -P
  chown -R postgres:postgres /var/lib/postgresql/data && chmod 700 /var/lib/postgresql/data
fi
exec gosu postgres postgres -c hot_standby=on
