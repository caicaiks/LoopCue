#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build/DerivedData}"
CONFIGURATION="${CONFIGURATION:-Debug}"

cd "$ROOT_DIR"
# 先基于 project.yml 重新生成工程，避免直接调用本脚本（不经
# make build 的 generate 目标）时使用陈旧工程导致新增文件缺失。
"$ROOT_DIR/scripts/generate.sh"
mkdir -p "$DERIVED_DATA_DIR"

xcodebuild \
  -project LoopCue.xcodeproj \
  -scheme LoopCue \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build
