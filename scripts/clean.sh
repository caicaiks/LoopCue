#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/.build/DerivedData}"

if [ -d "$DERIVED_DATA_DIR" ]; then
  rm -rf "$DERIVED_DATA_DIR"
  echo "已清理 $DERIVED_DATA_DIR"
else
  echo "没有需要清理的构建产物"
fi

