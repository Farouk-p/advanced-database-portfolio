#!/usr/bin/env bash
# Note: the failing statement in B/C aborts the tx; psql continues so ROLLBACK runs.
docker exec -i naijamart-pg psql -U naija -d naijamart < 01_commit_rollback.sql 2>&1 | tee evidence/demo1_commit_rollback.txt
