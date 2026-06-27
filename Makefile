.PHONY: help tools format format-all lint lint-all build test stage ci-check hooks-install

.DEFAULT_GOAL := help

SWIFT_FORMAT := xcrun swift-format
SWIFT_FORMAT_CONFIG := .swift-format
SWIFT_SOURCE_DIRS := Sources Tests

help:
	@printf "M4FanControl developer commands\n\n"
	@printf "  make tools         Check required local tools\n"
	@printf "  make format        Format changed Swift files with Xcode swift-format\n"
	@printf "  make format-all    Format all Swift sources explicitly\n"
	@printf "  make lint          Check changed Swift files without editing files\n"
	@printf "  make lint-all      Check all Swift sources explicitly\n"
	@printf "  make build         Build SwiftPM release binaries\n"
	@printf "  make test          Run SwiftPM tests\n"
	@printf "  make stage         Stage the menu bar app bundle via script/build_and_run.sh\n"
	@printf "  make ci-check      Local gate: lint + build + test\n"
	@printf "  make hooks-install Install optional Lefthook git hooks\n"

tools:
	@xcrun --find swift-format >/dev/null
	@swift --version >/dev/null
	@printf "tools: swift and swift-format are available\n"

format: tools
	@scripts/swift_format_changed.sh format

format-all: tools
	$(SWIFT_FORMAT) format --in-place --recursive --parallel \
		--configuration $(SWIFT_FORMAT_CONFIG) \
		$(SWIFT_SOURCE_DIRS)

lint: tools
	@scripts/swift_format_changed.sh lint

lint-all: tools
	$(SWIFT_FORMAT) lint --strict --recursive --parallel \
		--configuration $(SWIFT_FORMAT_CONFIG) \
		$(SWIFT_SOURCE_DIRS)

build:
	swift build -c release

test:
	swift test

stage:
	./script/build_and_run.sh stage

ci-check: lint build test
	@printf "ci-check: passed\n"

hooks-install:
	@command -v lefthook >/dev/null || { echo "lefthook is not installed. Install it with: brew install lefthook"; exit 69; }
	lefthook install
