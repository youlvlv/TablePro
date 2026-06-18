#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GO_DIR="$PROJECT_DIR/Plugins/DamengDriverPlugin/CDamengGo/damenggo"
HEADER_DEST="$PROJECT_DIR/Plugins/DamengDriverPlugin/CDamengGo/include/dameng_go.h"
LIBS_DIR="$PROJECT_DIR/Libs"
BUILD_DIR=$(mktemp -d)

trap "rm -rf $BUILD_DIR" EXIT

if ! command -v go &>/dev/null; then
    echo "Error: Go is not installed. Install with: brew install go"
    exit 1
fi

echo "==> Building dm-go-driver static library..."

cd "$GO_DIR"

if [ ! -f go.sum ]; then
    echo "==> Downloading dependencies..."
    go mod tidy
fi

echo "==> Building arm64..."
GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 \
    go build -buildmode=c-archive \
    -o "$BUILD_DIR/libdamenggo_arm64.a" .

echo "==> Building x86_64..."
GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 \
    go build -buildmode=c-archive \
    -o "$BUILD_DIR/libdamenggo_x86_64.a" .

echo "==> Creating universal binary..."
lipo -create \
    "$BUILD_DIR/libdamenggo_arm64.a" \
    "$BUILD_DIR/libdamenggo_x86_64.a" \
    -output "$LIBS_DIR/libdamenggo.a"

echo "==> Copying generated header..."
cp "$BUILD_DIR/libdamenggo_arm64.h" "$HEADER_DEST"

echo "==> Done!"
echo "  Library: $LIBS_DIR/libdamenggo.a"
echo "  Header:  $HEADER_DEST"
lipo -info "$LIBS_DIR/libdamenggo.a"
