#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build --product HyperTransfer --disable-sandbox
exec .build/debug/HyperTransfer
