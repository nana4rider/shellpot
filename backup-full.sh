#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] ${HOSTNAME}のフルバックアップに失敗しました" 1>&2
    exit 1
}
trap catch ERR

source "$HOME/config/common/storage.env"
source "$HOME/config/common/webhook.env"

function rotate_backups {
    cd "$BACKUP_DIR"

    if [ ! -f backup-full-1.img ]; then
        echo "backup-full-1.img not found, skipping rotation"
        return
    elif [ -f "backup-full-$MAX_BACKUPS_FULL.img" ]; then
        sudo rm "backup-full-$MAX_BACKUPS_FULL.img"
    fi

    # Shift backups
    for ((i = MAX_BACKUPS_FULL - 1; i >= 1; i--)); do
        if [ -f backup-full-$i.img ]; then
            sudo mv "backup-full-$i.img" "backup-full-$((i + 1)).img"
        fi
    done
}

function create_backup {
    # sudo fdisk -l
    # Device     Boot   Start      End  Sectors  Size Id Type
    # /dev/sda1          8192  1056767  1048576  512M  c W95 FAT32 (LBA)
    # /dev/sda2       1056768 62500000 61443233 29.3G 83 Linux
    #
    # count = 61443233{sda2のEnd} / 2048 の切り上げを下記コードのcount=に指定する
    COUNT=$(sudo fdisk -l "$STORAGE_SSD1" | tail -n1 | awk '{print int(($4 + 2047) / 2048)}')
    echo dd count="$COUNT"

    sudo dd if="$STORAGE_SSD1" of="$BACKUP_DIR/backup-full-1.img" oflag=direct bs=1M count="$COUNT"

    curl -fs -X POST \
        --json '{"content":"'"$HOSTNAME"'のフルバックアップが完了しました"}' \
        "$WEBHOOK_BACKUP"
}

rotate_backups
create_backup
