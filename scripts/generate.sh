#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "错误：未安装 xcodegen，请先运行 brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
echo "已生成 LoopCue.xcodeproj"

