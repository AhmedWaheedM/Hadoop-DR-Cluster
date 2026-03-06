#!/bin/bash
# start-cluster.sh — Master Orchestration Script
# Run this from dr-node01 to start the entire cluster in the correct order
#
# Startup Order (ORDER MATTERS):
#   1. ZooKeeper on dr-node01, dr-node02, dr-node03   (must be first)
#   2. JournalNodes on dr-node01, dr-node02, dr-node03 (must be before NN format)
#   3. Format + start Active NameNode on dr-node01
#   4. Bootstrap + start Standby NameNode on dr-node02
#   5. Start DataNodes + NodeManagers on dr-node03, dr-node04, dr-node05

set -e

HADOOP_HOME=/opt/hadoop
ZK_HOME=/opt/zookeeper
SCRIPTS_DIR=/shared/scripts

log() { echo ""; echo "══════════════════════════════════════════════"; echo "  [CLUSTER] $*"; echo "══════════════════════════════════════════════"; }
ok()  { echo "  OK $*"; }
err() { echo "  ERROR: Check Logs $*"; exit 1; }

[[ "$(hostname)" != "dr-node01" ]] && err "start-cluster.sh must be run from dr-node01"

# ── Step 1: Start ZooKeeper on all 3 ZK nodes 
log "STEP 1/5 — Starting ZooKeeper Ensemble"
for node in dr-node01 dr-node02 dr-node03; do
  echo "  → Starting ZooKeeper on $node"
  ssh root@$node "bash $SCRIPTS_DIR/zk-init.sh" &
done
wait
sleep 5

# Verify quorum formed
ok "Verifying ZooKeeper quorum..."
for node in dr-node01 dr-node02 dr-node03; do
  STATUS=$(ssh root@$node "$ZK_HOME/bin/zkServer.sh status 2>/dev/null | grep Mode")
  echo "  $node: $STATUS"
done

# ── Step 2: Start JournalNode on dr-node03 (dr-node01/02 start in their own scripts) 
log "STEP 2/5 — Starting JournalNodes on dr-node02 and dr-node03"
ssh root@dr-node02 "hdfs --daemon start journalnode" &
ssh root@dr-node03 "bash $SCRIPTS_DIR/dr-node03.sh" &
wait
sleep 3

# Verify all 3 JournalNodes are up
for node in dr-node01 dr-node02 dr-node03; do
  ssh root@$node "nc -z localhost 8485 && echo '  '$node' JournalNode UP' || echo '  '$node' JournalNode DOWN'"
done
# ── Step 3: Start Active NameNode on dr-node01 
log "STEP 3/5 — Starting Active NameNode on dr-node01"
bash $SCRIPTS_DIR/dr-node01.sh
ok "dr-node01 Active NameNode is up"

# ── Step 4: Bootstrap and start Standby NameNode on dr-node02 
log "STEP 4/5 — Starting Standby NameNode on dr-node02"
ssh root@dr-node02 "bash $SCRIPTS_DIR/dr-node02.sh"
ok "dr-node02 Standby NameNode is up"

# ── Step 5: Start worker nodes 
log "STEP 5/5 — Starting Worker Nodes (dr-node04, dr-node05)"
for node in dr-node04 dr-node05; do
  echo "  → Starting DataNode + NodeManager on $node"
  ssh root@$node "bash $SCRIPTS_DIR/workers.sh" &
done
wait
ok "Worker nodes started"

# ── Final Health Check 
log "CLUSTER HEALTH CHECK"
sleep 5

echo ""
echo "  HDFS HA Status:"
$HADOOP_HOME/bin/hdfs haadmin -getServiceState nn1 && echo "  nn1: active" || echo "  nn1: unknown"
$HADOOP_HOME/bin/hdfs haadmin -getServiceState nn2 && echo "  nn2: standby" || echo "  nn2: unknown"

echo ""
echo "  YARN RM HA Status:"
$HADOOP_HOME/bin/yarn rmadmin -getServiceState rm1 || echo "  rm1: unknown"
$HADOOP_HOME/bin/yarn rmadmin -getServiceState rm2 || echo "  rm2: unknown"

echo ""
echo "  HDFS Cluster Report:"
$HADOOP_HOME/bin/hdfs dfsadmin -report | grep -E "Live datanodes|Dead datanodes|DFS Used"

echo ""
ok "Cluster startup complete!"
echo "  HDFS UI  → http://localhost:9871  (dr-node01) / http://localhost:9872  (dr-node02)"
echo "  YARN UI  → http://localhost:8081  (dr-node01) / http://localhost:8082  (dr-node02)"