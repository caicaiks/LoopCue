DERIVED_DATA_DIR ?= .build/DerivedData
CONFIGURATION ?= Debug

.PHONY: help generate build release test clean run open

help: ## 显示所有命令
	@echo "可用命令："
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

generate: ## 重新生成 Xcode 工程（project.yml -> LoopCue.xcodeproj）
	./scripts/generate.sh

build: generate ## 构建 Debug
	./scripts/build.sh

release: generate ## 构建 Release
	CONFIGURATION=Release ./scripts/build.sh

test: generate ## 运行全部单元测试
	DERIVED_DATA_DIR="$(abspath $(DERIVED_DATA_DIR))" ./scripts/test.sh

clean: ## 清理本地构建产物（.build/DerivedData）
	./scripts/clean.sh

run: generate ## 构建并启动应用（菜单栏）
	./scripts/run.sh

open: generate ## 生成工程并用 Xcode 打开
	open LoopCue.xcodeproj
