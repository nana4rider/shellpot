#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    exit 1
}
trap catch ERR

cd ~/repository/home-wiki

git pull --rebase
git push
