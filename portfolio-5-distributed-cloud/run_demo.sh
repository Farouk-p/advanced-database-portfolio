#!/usr/bin/env bash
# Portfolio 5 demo. Run after: docker compose up -d
P="docker exec -i nm-pg-primary psql -U naija -d naijamart -x -q"
R="docker exec -i nm-pg-replica psql -U naija -d naijamart -q"
{
echo "##### PART A: PostgreSQL streaming replication (primary :5442 -> replica :5443)"
echo "--- replication status on PRIMARY"
echo "SELECT client_addr, state, sync_state FROM pg_stat_replication;" | $P
echo "--- replica is in recovery (read-only standby)?"
echo "SELECT pg_is_in_recovery();" | $R
echo "--- write on primary"
echo "INSERT INTO customers(full_name,email) VALUES ('Replica Test','replica-test-'||extract(epoch from now())::bigint||'@mail.ng') RETURNING customer_id, email;" | docker exec -i nm-pg-primary psql -U naija -d naijamart -q
sleep 2
echo "--- read the same row on REPLICA (replicated)"
echo "SELECT customer_id, email FROM customers WHERE full_name='Replica Test';" | $R
echo "--- try to write on REPLICA (must fail)"
echo "INSERT INTO customers(full_name,email) VALUES ('x','x@x.ng');" | $R 2>&1
echo "--- replication lag"
echo "SELECT now() - pg_last_xact_replay_timestamp() AS replay_delay;" | $R

echo; echo "##### PART B: MongoDB replica set rs0 (3 nodes) + failover"
docker exec nm-mongo1 mongosh --quiet --eval 'try{rs.status().ok}catch(e){rs.initiate({_id:"rs0",members:[{_id:0,host:"mongo1:27017"},{_id:1,host:"mongo2:27017"},{_id:2,host:"mongo3:27017"}]})}' >/dev/null
sleep 12
STATUS='rs.status().members.forEach(m=>print(m.name, m.stateStr))'
echo "--- members"; docker exec nm-mongo1 mongosh --quiet --eval "$STATUS"
PRIMARY=$(docker exec nm-mongo1 mongosh --quiet --eval 'print(rs.status().members.find(m=>m.stateStr=="PRIMARY").name.split(":")[0])')
echo "primary is: $PRIMARY"
docker exec "nm-$PRIMARY" mongosh --quiet --eval 'db.getSiblingDB("naijamart").orders.insertOne({_id:1,note:"written before failover"},{writeConcern:{w:"majority"}})' >/dev/null
echo "--- STOP the primary ($PRIMARY) to simulate failure"
docker stop "nm-$PRIMARY" >/dev/null
sleep 15
SURVIVOR=$([ "$PRIMARY" = "mongo1" ] && echo mongo2 || echo mongo1)
echo "--- members seen by $SURVIVOR after failure (new primary elected automatically)"
docker exec "nm-$SURVIVOR" mongosh --quiet --eval "$STATUS"
echo "--- data still available (read from new primary / secondary):"
docker exec "nm-$SURVIVOR" mongosh --quiet --eval 'db.getMongo().setReadPref("secondaryPreferred"); printjson(db.getSiblingDB("naijamart").orders.findOne({_id:1}))'
echo "--- write on new primary"
docker exec "nm-$SURVIVOR" mongosh --quiet --eval 'printjson(db.getSiblingDB("naijamart").orders.insertOne({_id:2,note:"written after failover"}).acknowledged)'
echo "--- restart old primary; it rejoins as SECONDARY and catches up"
docker start "nm-$PRIMARY" >/dev/null; sleep 15
docker exec "nm-$SURVIVOR" mongosh --quiet --eval "$STATUS"
docker exec "nm-$PRIMARY" mongosh --quiet --eval 'db.getMongo().setReadPref("secondary"); print("count on rejoined node:", db.getSiblingDB("naijamart").orders.countDocuments())'
} 2>&1 | tee evidence/demo_replication_failover.txt
