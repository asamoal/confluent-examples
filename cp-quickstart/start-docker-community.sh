#!/bin/bash

# Source library
source ../utils/helper.sh

curl -f -sS -o docker-compose.yml https://raw.githubusercontent.com/confluentinc/cp-all-in-one/${CONFLUENT_RELEASE_TAG_OR_BRANCH}/cp-all-in-one-community/docker-compose.yml || exit 1

./stop-docker.sh

docker-compose up -d

# Verify Kafka Connect worker has started
MAX_WAIT=180
echo "Waiting up to $MAX_WAIT seconds for Connect to start"
retry $MAX_WAIT check_connect_up connect || exit 1
sleep 2 # give connect an exta moment to fully mature
echo "connect has started!"

# Configure datagen connectors
curl -sS -o connector_pageviews_cos.config https://raw.githubusercontent.com/confluentinc/kafka-connect-datagen/master/config/connector_pageviews_cos.config || exit 1
curl -X POST -H "Content-Type: application/json" --data @connector_pageviews_cos.config http://localhost:8083/connectors
curl -sS -o connector_users_cos.config https://raw.githubusercontent.com/confluentinc/kafka-connect-datagen/master/config/connector_users_cos.config || exit 1
curl -X POST -H "Content-Type: application/json" --data @connector_users_cos.config http://localhost:8083/connectors

# Verify topics exist
MAX_WAIT=30
echo -e "\nWaiting up to $MAX_WAIT seconds for topics (pageviews, users) to exist"
retry $MAX_WAIT check_topic_exists broker broker:29092 pageviews || exit 1
retry $MAX_WAIT check_topic_exists broker broker:29092 users || exit 1
echo "Topics exist!"

# Run the KSQL queries
docker-compose exec ksqldb-cli bash -c "ksql http://ksqldb-server:8088 <<EOF
run script '/tmp/statements.sql';
exit ;
EOF"

printf "\n====== Successfully Completed ======\n\n"
