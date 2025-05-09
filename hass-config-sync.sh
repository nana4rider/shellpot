#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] "$(basename $0)"の実行中にエラーが発生しました" 1>&2
    cd $BASE_DIR && git reset --hard
    exit 1
}
trap catch ERR

source ~/config/hass-config-sync/app.env

BASE_DIR=~/repository/hass-config
REMOTE_FILES_LIST=~/config/hass-config-sync/files.txt

if [[ -f "$REMOTE_FILES_LIST" ]]; then
    mapfile -t TARGET_FILES <"$REMOTE_FILES_LIST"
else
    echo "[ERROR] 設定ファイル $REMOTE_FILES_LIST が見つかりません" 1>&2
    exit 1
fi

cd $BASE_DIR

git pull --rebase

cat "$REMOTE_FILES_LIST" | awk -F'/' '{print $1}' | sort -u | while read -r dir; do
    mkdir $dir -p
    find $dir -type f -delete
done

ssh "${HASS_USER}@${HASS_HOST}" "tar czf - -C / ${TARGET_FILES[*]}" | tar xzf - -C "."

git add -A
git commit --author="$COMMIT_AUTHOR" -m "update Home Assistant config files" || true
git push

# Alloy config file
BASE_DIR=~/repository/monitoring

cd $BASE_DIR

git pull --rebase

scp ${HASS_USER}@${HASS_HOST}:/config/alloy/config.alloy ~/repository/monitoring/alloy/config_hass.alloy

git add -A
git commit --author="$COMMIT_AUTHOR" -m "update Alloy config file" || true
git push
