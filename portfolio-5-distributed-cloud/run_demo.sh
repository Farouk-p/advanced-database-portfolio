#!/usr/bin/env bash
# Portfolio 5 demo. Start the containers first (docker compose up -d) and wait about 2 minutes for the replica.
P="docker exec -i fp-pg-primary psql -U farpoint -d farpoint -q"
R="docker exec -i fp-pg-replica psql -U farpoint -d farpoint -q"
{
echo "################ PART A: PostgreSQL replication (primary on :5442, replica on :5443)"
echo
echo "--- A1. The primary sees the replica and is streaming to it"
echo "SELECT state, sync_state FROM pg_stat_replication;" | $P
echo "--- A2. The replica holds the same data (customers / transaction log rows)"
echo "SELECT (SELECT count(*) FROM customers) AS customers, (SELECT count(*) FROM transaction_logs) AS log_rows;" | $R
echo "--- A3. The replica is a read-only standby"
echo "SELECT pg_is_in_recovery() AS is_standby;" | $R
echo "--- A4. A statement query can run on the replica (so reporting does not slow down the primary)"
echo "SELECT tx_type, direction, amount, balance_after FROM transaction_logs WHERE account_id = 1234 ORDER BY created_at DESC LIMIT 3;" | $R
echo "--- A5. A write on the replica is refused"
echo "INSERT INTO customers(full_name,email,phone,bvn) VALUES ('X','x@x.ng','0','22000000000');" | $R 2>&1
echo "--- A6. A deposit on the primary appears on the replica a moment later (asynchronous replication)"
echo "INSERT INTO deposits(account_id, amount, channel) VALUES (1, 12345, 'MOBILE');" | $P
sleep 1
echo "SELECT deposit_id, account_id, amount FROM deposits WHERE amount = 12345;" | $R
echo "--- A7. How far behind is the replica?"
echo "SELECT now() - pg_last_xact_replay_timestamp() AS replay_delay;" | $R

echo
echo "--- A8. SYNCHRONOUS replication: a commit now waits until the replica confirms it (no data loss)"
echo "ALTER SYSTEM SET synchronous_standby_names = '*'; SELECT pg_reload_conf();" | $P > /dev/null
sleep 2
echo "SELECT sync_state FROM pg_stat_replication;" | $P
echo "Commit with the replica UP (timed):"
s=$(python3 -c 'import time;print(time.time())')
echo "INSERT INTO deposits(account_id, amount, channel) VALUES (1, 111, 'MOBILE');" | $P
e=$(python3 -c 'import time;print(time.time())'); python3 -c "print('  took %.0f ms' % (($e-$s)*1000))"
echo "Now the replica goes DOWN. A commit on the primary now has to wait for it:"
docker stop fp-pg-replica > /dev/null
sleep 2
docker exec fp-pg-primary timeout 6 psql -U farpoint -d farpoint -q -c "INSERT INTO deposits(account_id, amount, channel) VALUES (1, 222, 'MOBILE');" 2>&1
echo "  -> exit status $? (124 = still waiting after 6 seconds). The bank chose to wait rather than risk losing a confirmed deposit."
echo "Switch back to asynchronous so the primary can accept writes alone again:"
echo "ALTER SYSTEM RESET synchronous_standby_names; SELECT pg_reload_conf();" | $P > /dev/null
sleep 1
echo "INSERT INTO deposits(account_id, amount, channel) VALUES (1, 333, 'MOBILE'); SELECT 'write accepted by the primary alone' AS result;" | $P
echo "Bring the replica back: it catches up on what it missed."
docker start fp-pg-replica > /dev/null; sleep 12
echo "SELECT count(*) AS missed_deposits_now_on_replica FROM deposits WHERE amount IN (111,222,333);" | $R

echo
echo "--- A9. FAILOVER: the primary is lost, the replica is promoted to take over"
docker stop fp-pg-primary > /dev/null
echo "SELECT pg_promote(wait => true) AS promoted;" | $R
echo "SELECT pg_is_in_recovery() AS is_standby_now;" | $R
echo "INSERT INTO deposits(account_id, amount, channel) VALUES (1, 444, 'MOBILE'); SELECT 'the promoted replica now accepts writes' AS result;" | $R
echo "SELECT count(*) AS deposits_survived FROM deposits WHERE amount IN (12345,111,222,333,444);" | $R
echo "(The old primary must be rebuilt as a standby before it rejoins, otherwise two servers would both accept writes.)"
docker start fp-pg-primary > /dev/null

echo
echo "################ PART B: MongoDB replica set rs0 (3 nodes)"
docker exec fp-mongo1 mongosh --quiet --eval 'try{rs.status().ok}catch(e){rs.initiate({_id:"rs0",members:[{_id:0,host:"mongo1:27017"},{_id:1,host:"mongo2:27017"},{_id:2,host:"mongo3:27017"}]})}' > /dev/null
sleep 12
STATUS='rs.status().members.forEach(m=>print("  ", m.name, m.stateStr))'
echo "--- B1. Members"; docker exec fp-mongo1 mongosh --quiet --eval "$STATUS"
PRIMARY=$(docker exec fp-mongo1 mongosh --quiet --eval 'print(rs.status().members.find(m=>m.stateStr=="PRIMARY").name.split(":")[0])')
echo "Primary is $PRIMARY. Write a transaction with majority acknowledgement (2 of 3 nodes must have it):"
docker exec "fp-$PRIMARY" mongosh --quiet --eval 'db=db.getSiblingDB("farpoint"); printjson(db.transactions.insertOne({_id:1, account_number:"3000000011", type:"DEPOSIT", amount:NumberDecimal("5000.00"), note:"before failover"},{writeConcern:{w:"majority"}}).acknowledged)'
echo "--- B2. STOP the primary ($PRIMARY)"
docker stop "fp-$PRIMARY" > /dev/null
sleep 15
SURVIVOR=$([ "$PRIMARY" = "mongo1" ] && echo mongo2 || echo mongo1)
echo "Members as seen by $SURVIVOR (a new primary is elected without human help):"
docker exec "fp-$SURVIVOR" mongosh --quiet --eval "$STATUS"
echo "--- B3. The confirmed transaction is still there, and writes still work"
docker exec "fp-$SURVIVOR" mongosh --quiet --eval 'db=db.getSiblingDB("farpoint"); db.getMongo().setReadPref("primaryPreferred"); printjson(db.transactions.findOne({_id:1}, {_id:1, note:1})); print("new write acknowledged:", db.transactions.insertOne({_id:2, account_number:"3000000011", type:"DEPOSIT", amount:NumberDecimal("7000.00"), note:"after failover"}).acknowledged)'
echo "--- B4. Only ONE node left would stop writes: stop a second node too"
OTHER=$(for n in mongo1 mongo2 mongo3; do [ "$n" != "$PRIMARY" ] && [ "$n" != "$SURVIVOR" ] && echo $n; done)
docker stop "fp-$OTHER" > /dev/null; sleep 12
docker exec "fp-$SURVIVOR" mongosh --quiet --eval 'db=db.getSiblingDB("farpoint"); try { db.transactions.insertOne({_id:3, note:"no majority"}, {writeConcern:{w:"majority", wtimeout:4000}}); print("accepted") } catch(e) { print("write NOT confirmed:", e.codeName || e.message) }; rs.status().members.forEach(m=>print("  ", m.name, m.stateStr))' 2>&1 | tail -6
echo "  (with 1 of 3 nodes alive there is no majority: the node steps down and refuses to confirm writes. Consistency over availability.)"
echo "--- B5. Restart the stopped nodes: they rejoin as secondaries and catch up"
docker start "fp-$PRIMARY" "fp-$OTHER" > /dev/null; sleep 20
docker exec "fp-$SURVIVOR" mongosh --quiet --eval "$STATUS"
docker exec "fp-$PRIMARY" mongosh --quiet --eval 'db=db.getSiblingDB("farpoint"); db.getMongo().setReadPref("secondaryPreferred"); print("documents visible on the rejoined node:", db.transactions.countDocuments({_id:{$in:[1,2]}}))'
} 2>&1 | tee evidence/demo_replication_failover.txt
