# --- Variables ---
SWIFT = swift
SWIFT_BUILD = $(SWIFT) build
SWIFT_TEST = $(SWIFT) test
SWIFT_CLEAN = $(SWIFT) package clean

# Flags
BUILD_FLAGS = -c debug -Xswiftc -warnings-as-errors
TEST_FLAGS = --enable-code-coverage -Xswiftc -warnings-as-errors

# --- Targets ---
.PHONY: all build release test clean format lint resolve help

all: build

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

## format: Format code using Apple's swift-format
format:
	@echo "Formatting code..."
	swift format --in-place --recursive .

## lint: Check code style using Apple's swift-format
lint:
	@echo "Linting code..."
	swift format lint --recursive .

## help: Show available commands
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^##' Makefile | sed -e 's/## //g' -e 's/:/	/g'
