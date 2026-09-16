#!/usr/bin/env bash
# Deploy (or validate) the ticket intake running ONLY its own Apex tests.
#
# Why RunSpecifiedTests instead of RunLocalTests: RunLocalTests runs every local
# test in the target org, including other teams' code we don't control. If one of
# those fails, it blocks this deploy. With RunSpecifiedTests Salesforce requires
# >=75% coverage on EACH class in the deploy, which this package's *Test classes provide.
#
# The test list is discovered from force-app/, so new *Test classes are picked up
# automatically.
#
# Usage:
#   scripts/deploy.sh <org-alias>              # deploy
#   scripts/deploy.sh <org-alias> --validate   # validate only (nothing is saved)
set -euo pipefail

ORG="${1:-}"
MODE="${2:-}"
if [[ -z "$ORG" ]]; then
  echo "Usage: $0 <org-alias> [--validate]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TESTS=()
for f in force-app/main/default/classes/*Test.cls; do
  TESTS+=("$(basename "$f" .cls)")
done
if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "No *Test classes found in force-app/" >&2
  exit 1
fi

CMD=start
[[ "$MODE" == "--validate" ]] && CMD=validate

echo "sf project deploy $CMD -o $ORG (tests: ${TESTS[*]})"
sf project deploy "$CMD" -o "$ORG" -d force-app -l RunSpecifiedTests -t "${TESTS[@]}" -w 60
