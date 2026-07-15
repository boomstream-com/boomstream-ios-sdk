#!/bin/sh
# Zero-dependency policy (docs/SDK_ARCHITECTURE.md §3): добавление внешней
# зависимости требует board-решения. Гейт работает на Linux (без Swift toolchain).
set -eu
if grep -nE '^[[:space:]]*\.package\(' Package.swift; then
  echo "zero-deps-gate: FAIL — external dependency declared in Package.swift" >&2
  exit 1
fi
if [ -s Package.resolved ]; then
  echo "zero-deps-gate: FAIL — non-empty Package.resolved committed" >&2
  exit 1
fi
echo "zero-deps-gate: OK"
