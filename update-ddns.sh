#!/bin/bash

set -eEuo pipefail
IP=$(curl -s https://api.ipify.org)
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  --config ~/config/update-ddns/curl.config -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"content\":\"$IP\"}"
