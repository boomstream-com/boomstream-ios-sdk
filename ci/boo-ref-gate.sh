#!/bin/sh
# Leak gate: ссылки на внутренний трекер не должны попадать в исходники.
set -eu
if grep -rInE 'BOO-[0-9]+' Sources Tests Package.swift 2>/dev/null; then
  echo "boo-ref-gate: FAIL — internal tracker references found in public sources" >&2
  exit 1
fi
echo "boo-ref-gate: OK"
