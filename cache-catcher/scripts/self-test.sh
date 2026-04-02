#!/bin/bash
# Hermetic smoke test for cache-catcher CLI (no real ~/.claude needed).
# Run from anywhere: bash src/cache-catcher/scripts/self-test.sh
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
CLI="$ROOT/cache-catcher.sh"
FAKE_HOME=$(mktemp -d "${TMPDIR:-/tmp}/cc-selftest.XXXXXX")
cleanup() { rm -rf "$FAKE_HOME"; }
trap cleanup EXIT

PROJ=/tmp/cc-hooker-selftest-proj
rm -rf "$PROJ"
mkdir -p "$PROJ"

SLUG=$(echo "$PROJ" | sed 's|^/||; s|/|-|g')
PROJ_DATA="$FAKE_HOME/.claude/projects/-$SLUG"
mkdir -p "$PROJ_DATA"

# 20 assistant turns: first half "bad" (no read), last half healthy — sessions should judge on tail only.
{
    i=1
    while [ "$i" -le 10 ]; do
        printf '%s\n' "{\"type\":\"assistant\",\"cache_creation_input_tokens\":80000,\"cache_read_input_tokens\":0,\"input_tokens\":1,\"output_tokens\":1,\"timestamp\":\"2026-01-01T12:$(printf %02d "$i"):00Z\"}"
        i=$((i + 1))
    done
    while [ "$i" -le 20 ]; do
        printf '%s\n' "{\"type\":\"assistant\",\"cache_creation_input_tokens\":2000,\"cache_read_input_tokens\":200000,\"input_tokens\":1,\"output_tokens\":1,\"timestamp\":\"2026-01-01T12:$(printf %02d "$i"):00Z\"}"
        i=$((i + 1))
    done
} > "$PROJ_DATA/mixed.jsonl"

printf '%s\n' '{"type":"user","id":"x"}' > "$PROJ_DATA/only-user.jsonl"

run() { HOME="$FAKE_HOME" bash "$CLI" "$@"; }

run help >/dev/null

OUT=$(run sessions -p "$PROJ" 2>&1) || true
case "$OUT" in
    *"integer expression"*)
        echo "FAIL: grep -c / integer bug still present"
        echo "$OUT"
        exit 1
        ;;
esac
case "$OUT" in
    *mixed*) ;;
    *)
        echo "FAIL: expected mixed session in output"
        echo "$OUT"
        exit 1
        ;;
esac
case "$OUT" in
    *mixed*healthy*) ;;
    *)
        echo "FAIL: expected mixed + healthy (last 10 turns are good)"
        echo "$OUT"
        exit 1
        ;;
esac

AP=$(run alias print 2>&1) || true
case "$AP" in
    alias\ cache-catcher=*) ;;
    *)
        echo "FAIL: alias print"
        echo "$AP"
        exit 1
        ;;
esac

echo "OK cache-catcher self-test"
