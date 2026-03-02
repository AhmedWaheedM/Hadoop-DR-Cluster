#!/bin/bash
# Node01 initialization: Active NameNode setup
set -e

echo "[node01] Initializing directories"
mkdir -p /var/hadoop/namenode /var/hadoop/journal

echo "[node01] Starting JournalNode"
if ! jps | grep -q JournalNode; then
    hdfs --daemon start journalnode
fi
sleep 2

echo "[node01] Formatting NameNode (if required)"
if [ ! -d "/var/hadoop/namenode/current" ]; then
    hdfs namenode -format -clusterId clusterA -force
else
    echo "[node01] NameNode already formatted"
fi

echo "[node01] Initializing ZooKeeper for HA"
hdfs zkfc -formatZK -force || true

echo "[node01] Starting NameNode"
if ! jps | grep -q NameNode; then
    hdfs --daemon start namenode
fi

echo "[node01] Starting ZKFC"
if ! jps | grep -q DFSZKFailoverController; then
    hdfs --daemon start zkfc
fi

echo "[node01] Node status:"
jps
