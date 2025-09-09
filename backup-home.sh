#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] ${HOSTNAME}のバックアップに失敗しました" 1>&2
    exit 1
}
trap catch ERR

SOURCE_DIR=$HOME
LOCAL_TMP="/tmp/backup-home.tar.gz"
MAX_BACKUPS=14
EXCLUDE_DIRS=("**/node_modules" "**/snapshot/*/*.jpg" ".cache" ".docker" "data/prometheus")

source ~/config/common/storage.env

function rotate_backups {
    cd "$BACKUP_DIR"

    if [ ! -f backup-home-1.tar.gz ]; then
        echo "backup-home-1.tar.gz not found, skipping rotation"
        return
    elif [ -f backup-home-$MAX_BACKUPS.tar.gz ]; then
        sudo rm "backup-home-$MAX_BACKUPS.tar.gz"
    fi

    # バックアップの世代管理（古いものからずらす）
    for ((i = MAX_BACKUPS - 1; i >= 1; i--)); do
        if [ -f backup-home-$i.tar.gz ]; then
            sudo mv "backup-home-$i.tar.gz" "backup-home-$((i + 1)).tar.gz"
        fi
    done
}

function create_backup {
    # 除外オプションを作成
    local exclude_args=()
    for dir in "${EXCLUDE_DIRS[@]}"; do
        exclude_args+=("--exclude=$dir")
    done

    # rsync でローカル `/tmp` にデータをコピー（ここで除外）
    local rsync_code
    set +e
    trap - ERR
    sudo rsync -aq --delete "${exclude_args[@]}" "$SOURCE_DIR/" /tmp/backup-home
    rsync_code=$?
    set -e
    trap catch ERR

    if [[ "$rsync_code" -ne 0 && "$rsync_code" -ne 24 ]]; then
        echo "[ERROR] rsync failed with code $rsync_code" >&2
        catch
    fi

    # tar コマンド(除外処理不要)
    if ! sudo tar -czf "$LOCAL_TMP" -C /tmp/backup-home .; then
        catch
    fi

    # ネットワークドライブへ転送
    sudo mv "$LOCAL_TMP" "$BACKUP_DIR/backup-home-1.tar.gz"

    # rsync の一時コピーを削除
    sudo rm -rf /tmp/backup-home

    echo "[INFO] ${HOSTNAME}のバックアップが完了しました"
}

rotate_backups
create_backup
