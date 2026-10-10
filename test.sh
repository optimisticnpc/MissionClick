#!/bin/zsh
set -eu
TASK_ROOT="${0:A:h}"
TASK_CACHE="$TASK_ROOT/.build/swift-module-cache"
TASK_TEST="$TASK_ROOT/.build/missionclick-selection-tests"
mkdir -p "$TASK_CACHE"
xcrun swiftc -swift-version 5 -module-cache-path "$TASK_CACHE" \
  "$TASK_ROOT/Source/WindowTarget.swift" "$TASK_ROOT/Tests/SelectionTests.swift" \
  -o "$TASK_TEST"
"$TASK_TEST"
