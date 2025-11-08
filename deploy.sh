#!/bin/bash
# shellcheck disable=SC2317,SC2029

set -eEuo pipefail

# shellcheck disable=SC2329
function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    exit 1
}
trap catch ERR

if [ -z "$1" ]; then
    echo "Error: No Service ID provided."
    exit 1
fi

source "$HOME/config/common/github.env"
source "$HOME/config/common/webhook.env"
source "$HOME/config/common/hass.env"

SERVICE_ID="$1"
DEPLOY_WEBHOOK_LOG="${2:-}"
DEPLOY_TEMP_DIR=$(mktemp -d)

# shellcheck disable=SC2329
function on_exit {
    local exit_code=$?
    local title
    local content
    local payload_json

    rm -rf "$DEPLOY_TEMP_DIR"

    if [ -n "$DEPLOY_WEBHOOK_LOG" ]; then
        if [ "$exit_code" -eq 0 ]; then
            title="Success: Deploy"
            content=""
            color="0x28a746"
        else
            title="Failure: Deploy"
            content=$WEBHOOK_MENTION_DEVELOPER
            color="0xcb2432"
        fi

        payload_json='{
          "username": "Deploy Shell",
          "content": "'$content'",
          "embeds": [
            {
              "title": "'$title'",
              "description": "Service ID: '$SERVICE_ID'",
              "color": '$(printf '%d' "$color")'
            }
          ]
        }'

        curl -s -X POST \
            -F "file=@$DEPLOY_WEBHOOK_LOG;filename=deploy_$(date +%s%3N).log" \
            -F "payload_json=$payload_json" \
            "$WEBHOOK_DEPLOY"

        rm "$DEPLOY_WEBHOOK_LOG"
    fi
}
trap on_exit EXIT

function update_repositories {
    local repositories=(
        "dockyard"
        "monitoring"
        "nana4-net"
        "shellpot"
    )
    for name in "${repositories[@]}"; do
        git -C "$HOME/repository/$name" pull &
    done
    wait
    sleep 1
}

function check_container_status {
    local running_count=0
    local interval=1
    local stable_running_seconds=4
    local max_wait_seconds=20

    echo "🔍 Waiting for all containers to stabilize..."
    for ((i = 1; i <= max_wait_seconds; i++)); do
        # コンテナの状態を取得
        container_states=$(docker compose ps --format json)

        # 一度でも Restarting 状態になっていたら即エラー
        if [ "$(echo "$container_states" | jq -s 'map(.State == "restarting") | any')" = 'true' ]; then
            echo "❌ Some containers are restarting. Aborting."
            docker compose logs | sed -E 's/\x1b\[[0-9;]*[mK]//g'
            docker compose down
            exit 1
        fi

        # すべてのコンテナが running ならカウントを進める
        if [ "$(echo "$container_states" | jq -s 'map(.State == "running") | all')" = 'true' ]; then
            ((running_count++)) || true
            echo "✅ All containers are running (${running_count}/${stable_running_seconds})..."

            if [[ $running_count -ge $stable_running_seconds ]]; then
                return 0
            fi
        else
            running_count=0
        fi

        sleep "$interval"
    done

    echo "❌ Service $SERVICE_ID failed to reach running state within $max_wait_seconds seconds."
    docker compose logs | sed -E 's/\x1b\[[0-9;]*[mK]//g'
    docker compose down
    exit 1
}

function check_remote_service_status {
    local host="$1"
    local retry_count=0
    local interval=2
    local max_wait_seconds=20
    local status

    echo "🔍 Checking service status on $host..."
    while ((retry_count < max_wait_seconds / interval)); do
        sleep "$interval"

        status=$(ssh "$host" "systemctl is-active $SERVICE_ID" 2>/dev/null)

        case "$status" in
        active)
            echo "✅ Service $SERVICE_ID is running on $host."
            return 0
            ;;
        activating)
            echo "⏳ Service $SERVICE_ID is still activating on $host... ($((retry_count * interval))s elapsed)"
            ((retry_count++))
            ;;
        *)
            echo "❌ Service $SERVICE_ID is in an unexpected state: $status"
            ssh "$host" "systemctl status $SERVICE_ID --no-pager"
            exit 1
            ;;
        esac
    done

    echo "❌ Service $SERVICE_ID failed to reach active state on $host within $max_wait_seconds seconds."
    ssh "$host" "systemctl status $SERVICE_ID --no-pager"
    exit 1
}

# local Docker container
if [ -f "$HOME/repository/dockyard/$SERVICE_ID/compose.yaml" ]; then
    echo "Processing Docker service for $SERVICE_ID..."
    cd "$HOME/repository/dockyard/$SERVICE_ID"

    update_repositories

    echo "Pulling latest Docker image for $SERVICE_ID..."
    docker compose pull || {
        echo "❌ Failed to pull latest Docker image for $SERVICE_ID."
        exit 1
    }

    echo "Starting service with the latest image..."
    docker compose up -d --force-recreate || {
        echo "❌ Failed to start Docker service $SERVICE_ID."
        exit 1
    }

    check_container_status

    docker compose logs | sed -E 's/\x1b\[[0-9;]*[mK]//g'
    echo "🎉 Deployment completed successfully."

    exit 0
fi

# remote systemd service
if [ "$SERVICE_ID" = "jema2mqtt" ]; then
    DEPLOY_TARGETS=("frontdoor.home" "backdoor.home")
    DEPLOY_DIR=~/app/$SERVICE_ID

    update_repositories

    RELEASE_URL="https://github.com/$GITHUB_USER/$SERVICE_ID/releases/latest/download/index.mjs.gz"

    # Download the latest release artifact
    echo "Downloading latest release from $RELEASE_URL..."
    curl -L -o "$DEPLOY_TEMP_DIR/index.mjs.gz" "$RELEASE_URL" || {
        echo "❌ Failed to download release artifact for $SERVICE_ID."
        exit 1
    }

    for HOST in "${DEPLOY_TARGETS[@]}"; do
        echo "🚀 Deploying to $HOST..."

        scp "$DEPLOY_TEMP_DIR/index.mjs.gz" "$HOST:$DEPLOY_DIR/" || {
            echo "❌ Failed to copy compressed file to $HOST."
            exit 1
        }

        ssh "$HOST" "gunzip -f $DEPLOY_DIR/index.mjs.gz" || {
            echo "❌ Failed to extract file on $HOST."
            exit 1
        }

        ssh "$HOST" "sudo systemctl restart $SERVICE_ID" || {
            echo "❌ Failed to restart service on $HOST."
            exit 1
        }

        check_remote_service_status "$HOST"

        ssh "$HOST" "journalctl -u $SERVICE_ID --since '30 seconds ago' --no-pager --output cat | sed -E 's/\x1b\[[0-9;]*[mK]//g'"
    done

    echo "🎉 Deployment completed successfully."
    exit 0
fi

# Home Assistant add-on
HA_ADDON_SLUG=$(ssh "${HASS_USER}@${HASS_HOST}" "ha addons list --raw-json | jq '.data.addons[] | select(.slug | test(\"_${SERVICE_ID}$\")) | .slug' -r")
if [ "$HA_ADDON_SLUG" != "" ]; then
    ssh "${HASS_USER}@${HASS_HOST}" "ha addons update $HA_ADDON_SLUG" || {
        echo "❌ Failed to update add-on."
        exit 1
    }
fi

echo "❌ [ERROR] Service $SERVICE_ID does not exist." 1>&2
exit 1
