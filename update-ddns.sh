#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    cd "$BASE_DIR" && git reset --hard
    exit 1
}
trap catch ERR

source "$HOME/config/update-ddns/app.env"

IP=$(curl -s https://api.ipify.org)
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  --config ~/config/update-ddns/curl.config -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"content\":\"$IP\"}"
