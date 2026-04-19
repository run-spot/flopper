#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_DIR="${ROOT_DIR}/flopper-ios/build/XCFrameworks/release/FlopperKitKmp.xcframework/ios-arm64_x86_64-simulator"
SHIM_ARCHIVE="${ROOT_DIR}/flopper-native/build/apple-shim/iosSimulatorArm64/libFlopperAppleShim.a"
SOURCE_FILE="${ROOT_DIR}/samples/apple/PodlessHostApp/AppDelegate.swift"
BUILD_DIR="${ROOT_DIR}/build/verify/podless-host-app"
APP_DIR="${BUILD_DIR}/PodlessHostApp.app"
APP_BINARY="${APP_DIR}/PodlessHostApp"
APP_BUNDLE_ID="com.runspot.flopper.PodlessHostApp"
MODE="smoke"
SIMULATOR_ID=""
SHOULD_REBUILD=0

pick_simulator_id() {
  local booted_id
  booted_id="$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone/ {print $(NF-1); exit}')"
  if [[ -n "${booted_id}" ]]; then
    echo "${booted_id}"
    return
  fi

  xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $(NF-1); exit}'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive)
      MODE="interactive"
      shift
      ;;
    --smoke)
      MODE="smoke"
      shift
      ;;
    --rebuild)
      SHOULD_REBUILD=1
      shift
      ;;
    --simulator-id)
      SIMULATOR_ID="${2:-}"
      shift 2
      ;;
    *)
      if [[ -z "${SIMULATOR_ID}" ]]; then
        SIMULATOR_ID="$1"
        shift
      else
        echo "error: unsupported argument '$1'" >&2
        exit 1
      fi
      ;;
  esac
done

SIMULATOR_ID="${SIMULATOR_ID:-$(pick_simulator_id)}"

if [[ -z "${SIMULATOR_ID}" ]]; then
  echo "error: no available iPhone simulator found" >&2
  exit 1
fi

if [[ "${SHOULD_REBUILD}" == "1" ]]; then
  (cd "${ROOT_DIR}" && ./gradlew --no-daemon :flopper-ios:assembleFlopperKitKmpXCFramework)
fi

if [[ ! -d "${FRAMEWORK_DIR}" ]]; then
  echo "error: missing XCFramework slice at ${FRAMEWORK_DIR}. Run ./gradlew :flopper-ios:assembleFlopperKitKmpXCFramework first or pass --rebuild." >&2
  exit 1
fi

if [[ ! -f "${SHIM_ARCHIVE}" ]]; then
  echo "error: missing Apple shim archive at ${SHIM_ARCHIVE}. Run ./gradlew :flopper-ios:assembleFlopperKitKmpXCFramework first or pass --rebuild." >&2
  exit 1
fi

mkdir -p "${APP_DIR}"

SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"

cat > "${APP_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>PodlessHostApp</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>PodlessHostApp</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSRequiresIPhoneOS</key>
  <true/>
  <key>UIApplicationSceneManifest</key>
  <dict/>
</dict>
</plist>
EOF

xcrun --sdk iphonesimulator swiftc \
  -parse-as-library \
  -sdk "${SDKROOT}" \
  -target arm64-apple-ios13.0-simulator \
  -F "${FRAMEWORK_DIR}" \
  -framework FlopperKitKmp \
  "${SOURCE_FILE}" \
  "${SHIM_ARCHIVE}" \
  -o "${APP_BINARY}"

open -a Simulator >/dev/null 2>&1 || true
xcrun simctl bootstatus "${SIMULATOR_ID}" -b || xcrun simctl boot "${SIMULATOR_ID}"
xcrun simctl install "${SIMULATOR_ID}" "${APP_DIR}"

if [[ "${MODE}" == "interactive" ]]; then
  xcrun simctl launch --console-pty --terminate-running-process "${SIMULATOR_ID}" "${APP_BUNDLE_ID}"
  exit 0
fi

SIMCTL_CHILD_FLOPPER_EXIT_AFTER_LAUNCH=1 \
  xcrun simctl launch --terminate-running-process "${SIMULATOR_ID}" "${APP_BUNDLE_ID}" >/dev/null
sleep 2

APP_CONTAINER="$(xcrun simctl get_app_container "${SIMULATOR_ID}" "${APP_BUNDLE_ID}" data)"
RUNTIME_FILE="${APP_CONTAINER}/Documents/flopper-runtime.txt"

if [[ ! -f "${RUNTIME_FILE}" ]]; then
  echo "error: runtime output not found at ${RUNTIME_FILE}" >&2
  exit 1
fi

cat "${RUNTIME_FILE}"
