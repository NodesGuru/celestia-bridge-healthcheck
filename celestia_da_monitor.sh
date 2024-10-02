#!/bin/bash
### TODO VARIABLES ###
#### TESTNET ####
# HC_API_KEY="" # healthchecks.io api key
# CELESTIA_SERVICE_NAME="celestia-bridged"
# CELESTIA_RPC_URL="https://rpc-1.testnet.celestia.nodes.guru"
# CELESTIA_BIN_PATH="/usr/local/bin/celestia"
# # CELESTIA_BRIDGE_NODE_STORE=/celestia/bridge/.celestia-bridge-mocha-4/ # testnet with ZFS
# CELESTIA_BRIDGE_NODE_STORE=$HOME/.celestia-bridge-mocha-4/ # testnet default
# CELESTIA_BRIDGE_NODE_URL="http://localhost:26658"
# CELESTIA_BRIDGE_METRICS_COLLECTOR_ADDRESS="otel.celestia-mocha.com" # testnet

#### MAINNET ####
HC_API_KEY="" # healthchecks.io api key
CELESTIA_SERVICE_NAME="celestia-bridged"
CELESTIA_RPC_URL="https://rpc.cosmos.directory/celestia"
CELESTIA_BIN_PATH="/usr/local/bin/celestia"
# CELESTIA_BRIDGE_NODE_STORE=/celestia/bridge/.celestia-bridge/ # mainnet with ZFS
CELESTIA_BRIDGE_NODE_STORE=$HOME/.celestia-bridge/ # mainnet default
CELESTIA_BRIDGE_NODE_URL="http://localhost:26658"
CELESTIA_BRIDGE_METRICS_COLLECTOR_ADDRESS="otel.celestia.observer" # mainnet
### TODO VARIABLES ###

if [[ -z $HC_API_KEY ]]; then
    echo "ERROR: HC_API_KEY not found."
    exit 1
fi

# Systemd
CELESTIA_BRIDGE_SYSTEMCTL_STATUS=$(/usr/bin/systemctl is-active $CELESTIA_SERVICE_NAME)
echo $CELESTIA_BRIDGE_SYSTEMCTL_STATUS

# Latest block from the Celestia node API
echo "Celestia Node API data..."
CELESTIA_BRIDGE_AUTH_TOKEN=$($CELESTIA_BIN_PATH bridge auth admin --node.store $CELESTIA_BRIDGE_NODE_STORE)
CELESTIA_BRIDGE_PEER_ID=$($CELESTIA_BIN_PATH p2p info --node.store $CELESTIA_BRIDGE_NODE_STORE --url $CELESTIA_BRIDGE_NODE_URL --token $CELESTIA_BRIDGE_AUTH_TOKEN | jq -r ".result.id")
CELESTIA_BRIDGE_HEIGHT=$($CELESTIA_BIN_PATH header sync-state --node.store $CELESTIA_BRIDGE_NODE_STORE --url $CELESTIA_BRIDGE_NODE_URL --token $CELESTIA_BRIDGE_AUTH_TOKEN | jq -r ".result.height")
echo $CELESTIA_BRIDGE_PEER_ID $CELESTIA_BRIDGE_AUTH_TOKEN $CELESTIA_BRIDGE_HEIGHT

# Logs
CELESTIA_BRIDGE_LATEST_DATA=$(journalctl -u $CELESTIA_SERVICE_NAME -n 100 --no-pager -o cat | grep -Ei "new network head" | awk '{for (i=NF-3; i<=NF; i++) {printf $i""}; print ""}' | tail -n 1)
CELESTIA_BRIDGE_LATEST_HEIGHT=$(echo $CELESTIA_BRIDGE_LATEST_DATA | jq .height)

# Get latest height from the chain (logs data)
echo "Celestia Node logs data..."
CELESTIA_BRIDGE_LATEST_BLOCK_DATA=$(curl -4 -s $CELESTIA_RPC_URL/block?height=$CELESTIA_BRIDGE_LATEST_HEIGHT)
CELESTIA_BRIDGE_LATEST_BLOCK_DATE=$(echo $CELESTIA_BRIDGE_LATEST_BLOCK_DATA | jq -r ".result.block.header.time")
CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP=$(date -d "$CELESTIA_BRIDGE_LATEST_BLOCK_DATE" "+%s")
CELESTIA_BRIDGE_CURRENT_TIMESTAMP=$(date +%s)
CELESTIA_BRIDGE_LOGS_TIMESTAMP_DIFF=$(($CELESTIA_BRIDGE_CURRENT_TIMESTAMP - $CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP))
echo $CELESTIA_BRIDGE_LATEST_DATA $CELESTIA_BRIDGE_LATEST_HEIGHT $CELESTIA_BRIDGE_LATEST_BLOCK_DATE $CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP $CELESTIA_BRIDGE_CURRENT_TIMESTAMP

# Get latest height from the chain (state data)
CELESTIA_BRIDGE_LATEST_BLOCK_DATA=$(curl -4 -s $CELESTIA_RPC_URL/block?height=$CELESTIA_BRIDGE_HEIGHT)
CELESTIA_BRIDGE_LATEST_BLOCK_DATE=$(echo $CELESTIA_BRIDGE_LATEST_BLOCK_DATA | jq -r ".result.block.header.time")
CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP=$(date -d "$CELESTIA_BRIDGE_LATEST_BLOCK_DATE" "+%s")
CELESTIA_BRIDGE_CURRENT_TIMESTAMP=$(date +%s)
echo $CELESTIA_BRIDGE_LATEST_DATA $CELESTIA_BRIDGE_HEIGHT $CELESTIA_BRIDGE_LATEST_BLOCK_DATE $CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP $CELESTIA_BRIDGE_CURRENT_TIMESTAMP

# Diff
CELESTIA_BRIDGE_STATE_TIMESTAMP_DIFF=$(($CELESTIA_BRIDGE_CURRENT_TIMESTAMP - $CELESTIA_BRIDGE_LATEST_BLOCK_TIMESTAMP))
echo "Logs diff:" $CELESTIA_BRIDGE_LOGS_TIMESTAMP_DIFF "seconds"
echo "State diff:" $CELESTIA_BRIDGE_STATE_TIMESTAMP_DIFF "seconds"

# Metrics server connectivity
CELESTIA_BRIDGE_METRICS_COLLECTOR_IP=$(nslookup $CELESTIA_BRIDGE_METRICS_COLLECTOR_ADDRESS | awk '/^Address: / { print $2 }')
CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA=$(sudo lsof -i -P -n | grep ESTABLISHED | grep -Ei $CELESTIA_BRIDGE_METRICS_COLLECTOR_IP)
if [[ -z $CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA ]]; then
    echo "Empty CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA, retry..."
    sleep 5
    CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA=$(sudo lsof -i -P -n | grep ESTABLISHED | grep -Ei $CELESTIA_BRIDGE_METRICS_COLLECTOR_IP)
fi
echo $CELESTIA_BRIDGE_METRICS_COLLECTOR_ADDRESS $CELESTIA_BRIDGE_METRICS_COLLECTOR_IP $CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA


if [[ "$CELESTIA_BRIDGE_SYSTEMCTL_STATUS" != "active" || $CELESTIA_BRIDGE_STATE_TIMESTAMP_DIFF -gt 180 || -z $CELESTIA_BRIDGE_HEIGHT || -z $CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA ]]; then
    echo "ERROR: Something went wrong"
    echo "CELESTIA_BRIDGE_SYSTEMCTL_STATUS" $CELESTIA_BRIDGE_SYSTEMCTL_STATUS 
    echo "CELESTIA_BRIDGE_STATE_TIMESTAMP_DIFF" $CELESTIA_BRIDGE_STATE_TIMESTAMP_DIFF 
    echo "CELESTIA_BRIDGE_HEIGHT" $CELESTIA_BRIDGE_HEIGHT 
    echo "CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA" $CELESTIA_BRIDGE_METRICS_COLLECTOR_DATA
    HC_RESULT=$((HC_RESULT + 1))
  else
    echo "SUCCESS: Metrics is OK"
fi

# healthchecks.io
if [[ $HC_RESULT -gt 0 ]]; then
    echo "ERROR: Healthcheck failed with $HC_RESULT errors."
    curl -m 10 -4 -fsS --retry 3 --data-raw "$HC_RESULT" https://hc-ping.com/$HC_API_KEY/fail >/dev/null
else
    echo "SUCCESS: Healthcheck passed successfully."
    curl -m 10 -4 -fsS --retry 3 --data-raw "$HC_RESULT" https://hc-ping.com/$HC_API_KEY >/dev/null
fi