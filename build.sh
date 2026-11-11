#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 [Release|Debug]"
    echo "Build a signed Apple TV app (default: Release)."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

configuration="${1:-Release}"
if [[ $# -gt 1 || ( "$configuration" != "Release" && "$configuration" != "Debug" ) ]]; then
    usage >&2
    exit 1
fi

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
derived_data_path="/tmp/ATV-BilibiliGlobal-device"

xcodebuild \
    -project "$project_dir/BiliBiliGlobal.xcodeproj" \
    -scheme BiliBiliGlobal \
    -configuration "$configuration" \
    -destination 'generic/platform=tvOS' \
    -derivedDataPath "$derived_data_path" \
    -allowProvisioningUpdates \
    build

echo "Built: $derived_data_path/Build/Products/$configuration-appletvos/BiliBiliGlobal.app"
