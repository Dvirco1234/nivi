#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -O Sources/DictatoCore/*.swift Tools/core-tests/main.swift -o .build/core-tests
.build/core-tests
