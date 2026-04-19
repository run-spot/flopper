#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCFRAMEWORK_DIR="${ROOT_DIR}/flopper-ios/build/XCFrameworks/release/FlopperKitKmp.xcframework"
SIMULATOR_SLICE_DIR="${XCFRAMEWORK_DIR}/ios-arm64_x86_64-simulator"
SHIM_ARCHIVE="${ROOT_DIR}/flopper-native/build/apple-shim/iosSimulatorArm64/libFlopperAppleShim.a"
SMOKE_SOURCE="${ROOT_DIR}/samples/apple/PodlessSmoke/main.swift"
OUTPUT_DIR="${ROOT_DIR}/build/verify/apple-xcframework"
OUTPUT_BIN="${OUTPUT_DIR}/PodlessSmoke"

if [[ ! -d "${SIMULATOR_SLICE_DIR}/FlopperKitKmp.framework" ]]; then
  echo "error: missing simulator XCFramework slice at ${SIMULATOR_SLICE_DIR}" >&2
  echo "run ./gradlew :flopper-ios:assembleFlopperKitKmpXCFramework first" >&2
  exit 1
fi

if [[ ! -f "${SHIM_ARCHIVE}" ]]; then
  echo "error: missing native Apple shim archive at ${SHIM_ARCHIVE}" >&2
  echo "run ./gradlew :flopper-ios:assembleFlopperKitKmpXCFramework first" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)"

xcrun --sdk iphonesimulator swiftc \
  -sdk "${SDKROOT}" \
  -target arm64-apple-ios13.0-simulator \
  -F "${SIMULATOR_SLICE_DIR}" \
  -framework FlopperKitKmp \
  "${SMOKE_SOURCE}" \
  "${SHIM_ARCHIVE}" \
  -o "${OUTPUT_BIN}"

echo "Podless Apple XCFramework smoke build succeeded:"
echo "  ${OUTPUT_BIN}"
