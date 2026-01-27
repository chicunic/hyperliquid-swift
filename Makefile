# --- Variables ---
SWIFT = swift
SWIFT_BUILD = $(SWIFT) build
SWIFT_TEST = $(SWIFT) test
SWIFT_CLEAN = $(SWIFT) package clean
SOURCES = Sources Tests

# Flags
BUILD_FLAGS = -c debug -Xswiftc -warnings-as-errors
TEST_FLAGS = --enable-code-coverage -Xswiftc -warnings-as-errors

# --- Targets ---
.PHONY: all build release test clean check fix resolve help

all: build

## check: Check code style (SwiftLint + swift-format) - use in CI
check:
	@echo "Checking code style..."
	@swiftlint --config .swiftlint.yml --strict
	@swift format lint --configuration .swift-format --recursive $(SOURCES)

## fix: Fix code style issues (SwiftLint autocorrect + swift-format)
fix:
	@echo "Fixing code style..."
	@swiftlint --config .swiftlint.yml --fix
	@swift format --configuration .swift-format --recursive --in-place $(SOURCES)

## build: Build the project in debug mode
build:
	@echo "Building..."
	$(SWIFT_BUILD) $(BUILD_FLAGS)

## release: Build the project in release mode
release:
	@echo "Building for release..."
	$(SWIFT_BUILD) -c release

## test: Run all unit tests
test:
	@echo "Running tests..."
	$(SWIFT_TEST) $(TEST_FLAGS)

## clean: Remove build artifacts
clean:
	@echo "Cleaning..."
	$(SWIFT_CLEAN)
	rm -rf .build

## resolve: Resolve package dependencies
resolve:
	@echo "Resolving dependencies..."
	$(SWIFT) package resolve

## help: Show available commands
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^##' Makefile | sed -e 's/## //g' -e 's/:/	/g'
