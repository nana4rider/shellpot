#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    cd "$BASE_DIR" && git reset --hard
    exit 1
}
trap catch ERR

source "$HOME/config/grafana-sync/app.env"

BASE_DIR=$HOME/repository/monitoring/grafana/export
GRAFANA_API="http://$GRAFANA_HOST/api"

fetch_api() {
    local path="$1"
    echo "[INFO] fetch $GRAFANA_API$path" 1>&2
    curl -fs --config ~/config/grafana-sync/curl.config -X GET "$GRAFANA_API$path"
}

cd "$BASE_DIR"

fetch_api "/health" | jq

git pull --rebase

find . -type f -delete

for uid in $(fetch_api "/search" | jq -r '.[] | select(.type == "dash-db") | .uid'); do
    fetch_api "/dashboards/uid/$uid" | jq '.dashboard' >"dashboards/$uid.json"
done

for uid in $(fetch_api "/v1/provisioning/alert-rules" | jq -r '.[].uid'); do
    fetch_api "/v1/provisioning/alert-rules/$uid" | jq '.' >"alert/rules/$uid.json"
done

fetch_api "/v1/provisioning/templates" | jq '.' >"alert/templates.json"

git add -A
git commit --author="$COMMIT_AUTHOR" -m "update Grafana sync files" || true
git push
