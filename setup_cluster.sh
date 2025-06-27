#!/bin/bash

# === EDIT THESE VARIABLES ===
USER="entall"
NODE0="node-0"
NODE1="node-1"
ALL_NODES=("node0" "node1" "node2" "node3" "node4" "node5")
NODE0_IP="10.10.1.1"  # Change to actual IP
NODE1_IP="10.10.1.2"  # Change to actual IP
IB_DEV_ID=3
IB_GID_IDX=3
CONN_TYPE="ROCE"
DITTO_DIR="~/Ditto"

echo "== Step 1: Install dependencies on all nodes"
for node in "${ALL_NODES[@]}"; do
  sudo ssh "$node" "
    cd $DITTO_DIR/scripts &&
    chmod +x setup-env.sh
    tmux new -d -s setup_env './setup-env.sh'
  "
done

echo "== Step 4: Configure Memcached on Node-0"
sudo ssh "$NODE0" "
  sudo sed -i 's/^-l .*/-l $NODE0_IP/' /etc/memcached.conf &&
  echo -e '-I 128m\n-m 2048' | sudo tee -a /etc/memcached.conf &&
  sudo service memcached restart
"

echo "== Step 5: Modify experiment configs on all nodes"
for node in "${ALL_NODES[@]}"; do
  sudo ssh "$node" "
    cd $DITTO_DIR/experiments &&
    python modify_config.py memory_ip_list=[\"$NODE1_IP\"] &&
    python modify_config.py ib_dev_id=$IB_DEV_ID &&
    python modify_config.py conn_type=\"$CONN_TYPE\" &&
    python modify_config.py ib_gid_idx=$IB_GID_IDX
  "
done

echo "== Step 6: Update shell_settings.sh on all nodes"
for node in "${ALL_NODES[@]}"; do
  sudo ssh "$node" "
    sed -i \"s/^memcached_ip=.*/memcached_ip=$NODE0_IP/\" $DITTO_DIR/experiments/scripts/shell_settings.sh
  "
done

echo "== Step 7: Enable hugepages on Node-1"
sudo ssh "$NODE1" "echo 10240 | sudo tee /proc/sys/vm/nr_hugepages"

# echo "== Step 9: Download workload on Node-0"
# sudo ssh "$NODE0" "
#   cd $DITTO_DIR/experiments/workloads &&
#   chmod +x download_all.sh &&
#   ./download_all.sh &&
#   nohup python3 -m http.server 8000 &
# "

# echo "== Step 10: Download workload from Node-0 on other nodes"
# for node in "${ALL_NODES[@]}"; do
#   [[ "$node" == "$NODE0" ]] && continue
#   ssh "$USER@$node" "
#     cd $DITTO_DIR/experiments/workloads &&
#     ./download_all_from_peer.sh $NODE0:8000
#   "
# done

# echo "== Step 11: Stop HTTP server on Node-0"
# ssh "$USER@$NODE0" "pkill -f 'http.server'"

# echo "== Setup completed. Run benchmark from Node-0:"
# echo "cd $DITTO_DIR/experiments/scripts && python3 kick-the-tires.py 256 ycsbc"
