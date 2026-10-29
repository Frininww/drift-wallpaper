#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${CONFIGURATION:-release}"
export MACOSX_DEPLOYMENT_TARGET=13.0
app="dist/Drift.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

if [[ "${1:-}" == "--universal" ]]; then
    swift build -c "$configuration" --arch arm64 --arch x86_64
    bin_dir="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c "$configuration"
    bin_dir="$(swift build -c "$configuration" --show-bin-path)"
fi
cp "$bin_dir/Drift" "$app/Contents/MacOS/Drift"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp -R "$bin_dir/Drift_Drift.bundle" "$app/Contents/Resources/"
swift scripts/GenerateIcon.swift "$app/Contents/Resources/Drift.icns"

# A local ad-hoc signature supports integrity checking, not developer identity.
# Supply a Developer ID identity to produce a distributable signed build.
codesign --force --deep --options runtime --sign "${SIGNING_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
echo "Built $PWD/$app"
