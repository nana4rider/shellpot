#!/bin/bash

set -eEuo pipefail

function catch {
    echo "[ERROR] $(basename "$0")の実行中にエラーが発生しました" 1>&2
    exit 1
}
trap catch ERR

source "$HOME/config/common/github.env"

find "$HOME/repository/dockyard" -name "compose.yaml" | while read -r file; do
    yq ".services[].image | select(. != null and startswith(\"$GITHUB_USER\"))" "$file" -r | while read -r image; do
        docker pull "$image"
        echo
    done
done
