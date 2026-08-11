#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build/DerivedData}"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/LoopCue.app"

cd "$ROOT_DIR"

if [ ! -d "$APP_PATH" ]; then
  echo "未找到构建产物，先执行 build"
  ./scripts/build.sh
fi

open "$APP_PATH"
echo "已启动 LoopCue（请查看菜单栏图标）"

