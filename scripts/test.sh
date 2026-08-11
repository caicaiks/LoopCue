#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build/DerivedData}"

cd "$ROOT_DIR"
mkdir -p "$DERIVED_DATA_DIR"

# 说明：单元测试运行器需要连接系统的 testmanagerd 服务，
# 因此 xcodebuild test 必须在沙盒外（非受限环境）执行。
xcodebuild \
  -project LoopCue.xcodeproj \
  -scheme LoopCue \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  test "$@"

