#!/bin/sh
# Hardcoded-credential guard (docs/SDK_ARCHITECTURE.md §8): литеральные ключи
# и токены запрещены в git-tracked source. Ключи приходят из xcconfig/CI env.
set -eu
PATTERN='(apiKey|api_key|userAgentToken|password|secret)[[:space:]]*[:=][[:space:]]*"[A-Za-z0-9+/_-]{16,}"'
if grep -rInE "$PATTERN" Sources Example 2>/dev/null; then
  echo "secret-grep-gate: FAIL — hardcoded credential-looking literal found" >&2
  exit 1
fi
echo "secret-grep-gate: OK"
