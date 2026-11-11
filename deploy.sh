#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <device-uuid> [Release|Debug]"
    echo "Install and launch an existing Apple TV build (default: Release)."
    echo "Find device UUIDs with: xcrun devicectl list devices"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

configuration="${2:-Release}"
if [[ $# -lt 1 || $# -gt 2 || -z "${1:-}" || ( "$configuration" != "Release" && "$configuration" != "Debug" ) ]]; then
    usage >&2
    exit 1
fi

device_uuid="$1"
app_path="/tmp/ATV-BilibiliGlobal-device/Build/Products/$configuration-appletvos/BiliBiliGlobal.app"
if [[ ! -d "$app_path" ]]; then
    echo "Build not found: $app_path" >&2
    echo "Run build.sh $configuration first." >&2
    exit 1
fi

xcrun devicectl device install app --device "$device_uuid" "$app_path"
xcrun devicectl device process launch --device "$device_uuid" \
    --terminate-existing com.etan.tv.BiliBiliGlobal
