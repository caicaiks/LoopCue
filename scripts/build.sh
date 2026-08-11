#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"

cd "$ROOT_DIR"
mkdir -p "$DERIVED_DATA_DIR"

xcodebuild \
  -project LoopCue.xcodeproj \
  -scheme LoopCue \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

