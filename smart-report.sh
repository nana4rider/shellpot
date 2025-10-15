#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    exit 1
}
trap catch ERR

source "$HOME/config/common/storage.env"
source "$HOME/config/common/webhook.env"

TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

sudo smartctl -d sat -A "$STORAGE_SSD1" | grep -v "Unknown_Attribute" >"$TMP_FILE"

MESSAGE="$WEBHOOK_MENTION_GEMINI 結果を解析して、健康状態の概要を教えてください。"

curl -fs -X POST "$WEBHOOK_SMART" \
    -F "file=@$TMP_FILE;type=text/plain" \
    -F "payload_json={\"username\": \"S.M.A.R.T. Report\", \"content\": \"${MESSAGE}\"}"
