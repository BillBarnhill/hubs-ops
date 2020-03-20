#!/usr/bin/env bash

if [[ -z "$1" || -z "$2" ]]; then
  echo -e "
Usage: tunnel.sh <host-type|hostname> <from-port> [to-port] [environment]

Opens a SSH tunnel via the bastion to a random host of type <host-type> or host <hostname> between two ports.

Expects ssh-agent to have mozilla mr ssh key registered and present in ~/.ssh/mozilla_mr_id_rsa.
"
  exit 1
fi

HOST_TYPE_OR_NAME=$1
FROM=$2
TO=$3
ENVIRONMENT=$4

[[ -z "$TO" ]] && TO=$FROM
[[ -z "$ENVIRONMENT" ]] && ENVIRONMENT=dev

REGION="us-west-1"

BASTION_IP=$(dig +short bastion-$ENVIRONMENT.reticulum.io | shuf | head -n1)
echo $BASTION_IP

if [[ $HOST_TYPE_OR_NAME == *"."* ]] ; then
  TARGET_IP=$(dig +short $HOST_TYPE_OR_NAME | shuf | head -n1)
elif [[ $HOST_TYPE_OR_NAME == *"-"* ]] ; then
  EC2_INFO=$(aws ec2 --region $REGION describe-instances)

  # it's a hostname
  TARGET_IP=$(echo $EC2_INFO | jq -r ".Reservations | map(.Instances) | flatten | map(select(any(.State ; .Name == \"running\"))) | map(select(any(.Tags // [] | from_entries ; .[\"Name\"] == \"${HOST_TYPE_OR_NAME}\"))) | .[] | .PrivateIpAddress" | shuf | head -n1)
else
  EC2_INFO=$(aws ec2 --region $REGION describe-instances)

  # it's a host type
  TARGET_IP=$(echo $EC2_INFO | jq -r ".Reservations | map(.Instances) | flatten | map(select(any(.State ; .Name == \"running\"))) | map(select(any(.Tags // [] | from_entries ; .[\"host-type\"] == \"${ENVIRONMENT}-${HOST_TYPE_OR_NAME}\"))) | .[] | .PrivateIpAddress" | shuf | head -n1)
fi

echo "ssh -i ~/.ssh/mozilla_mr_id_rsa -L \"0.0.0.0:$TO:$TARGET_IP:$FROM\" \"ubuntu@$BASTION_IP\""
ssh -i ~/.ssh/mozilla_mr_id_rsa -L "0.0.0.0:$TO:$TARGET_IP:$FROM" "ubuntu@$BASTION_IP"
