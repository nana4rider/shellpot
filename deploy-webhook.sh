#!/bin/bash

set -eEuo pipefail

TARGET_SCRIPT=/home/$DEPLOY_USER/repository/shellpot/deploy.sh
SERVICE_ID="$1"
LOG_FILE=/tmp/deploy-webhook.log
SSH_COMMAND="ssh -o StrictHostKeyChecking=no $DEPLOY_USER@deploy-target"

if [ "$SERVICE_ID" = "deploy-webhook" ]; then
    $SSH_COMMAND "nohup $TARGET_SCRIPT $SERVICE_ID >$LOG_FILE 2>&1 &"
else
    $SSH_COMMAND "$TARGET_SCRIPT $SERVICE_ID >$LOG_FILE 2>&1"
fi
