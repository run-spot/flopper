#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <version> <artifact-url> <checksum>" >&2
  exit 1
fi

VERSION="$1"
ARTIFACT_URL="$2"
CHECKSUM="$3"

cat <<EOF
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlopperKitKmp",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "FlopperKitKmp",
            targets: ["FlopperKitKmp"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "FlopperKitKmp",
            url: "$ARTIFACT_URL",
            checksum: "$CHECKSUM"
        ),
    ]
)
EOF
