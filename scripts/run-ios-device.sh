#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
device_id="${READING_TRACKER_DEVICE_ID:-00008150-00024C3E22EA401C}"
derived_data="${READING_TRACKER_DERIVED_DATA:-/private/tmp/ReadingTracker-Debug-build}"
build_log="$derived_data/device-build.log"
mkdir -p "$derived_data"

echo "Building Debug incrementally for your iPhone…"
# Reuse the same build cache. Never clean, archive, export, or uninstall here.
if ! xcodebuild \
  -project "$repo_root/ios/ReadingTracker.xcodeproj" \
  -scheme ReadingTracker \
  -configuration Debug \
  -destination "id=$device_id" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates build > "$build_log" 2>&1; then
  tail -n 80 "$build_log"
  echo "Build failed. Full log: $build_log" >&2
  exit 1
fi

echo "Updating the app on your iPhone…"
xcrun devicectl device install app --device "$device_id" \
  "$derived_data/Build/Products/Debug-iphoneos/ReadingTracker.app"

echo "Launching Reading Tracker…"
xcrun devicectl device process launch --device "$device_id" \
  --terminate-existing com.ninanguyen26.readingtracker
echo "Done. Build log: $build_log"
