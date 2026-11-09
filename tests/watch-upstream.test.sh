#!/bin/bash
# Deterministic tests for scripts/watch-upstream.sh using a mocked gh CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/watch-upstream.sh"
MOCK="$ROOT/tests/helpers/mock-gh.sh"
FIXTURE="$ROOT/tests/fixtures/upstream-releases.json"
export WATCH_RETRY_MAX=3
export WATCH_RETRY_BASE_SECONDS=0
export REPO="sudoytang/codex-loongarch-oldworld"

PASS=0
FAIL=0

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" = "$want" ]; then
    echo "PASS $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL $msg"
    echo "  got:  [$got]"
    echo "  want: [$want]"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS $msg"
    PASS=$((PASS + 1))
  else
    echo "FAIL $msg"
    echo "  missing: [$needle]"
    echo "  in: [$haystack]"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_count() {
  local file="$1" want="$2" msg="$3"
  local got=0
  if [ -f "$file" ]; then
    got="$(grep -c . "$file" || true)"
  fi
  assert_eq "$got" "$want" "$msg"
}

run_watch() {
  local state="$1"
  mkdir -p "$state"
  cp "$FIXTURE" "$state/api.json"
  : > "$state/log"
  export GH_MOCK_STATE="$state"
  export GH="$MOCK"
  set +e
  OUT="$("$SCRIPT" 2>"$state/stderr")"
  RC=$?
  set -e
  ERR="$(cat "$state/stderr")"
}

write_lines() {
  local file="$1"
  shift
  : > "$file"
  local line
  for line in "$@"; do
    printf '%s\n' "$line" >> "$file"
  done
}

echo "== transient then success (HTTP 504, then list + existing release)"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 504 200
write_lines "$STATE/releases" "v0.167.0"
run_watch "$STATE"
assert_eq "$RC" "0" "transient then success exits 0"
assert_contains "$OUT" "Latest stable upstream: rust-v0.167.0 (version 0.167.0)" "selects rust-v0.167.0 after retry"
assert_contains "$OUT" "already has a release" "skips build when v0.167.0 exists"
assert_file_count "$STATE/api.calls" "2" "api called twice (504 then 200)"
assert_file_count "$STATE/workflow.calls" "0" "no build dispatch after existing-release hit"
assert_contains "$ERR" "Transient GitHub read failure (HTTP 504)" "logs transient retry"
rm -rf "$STATE"

echo "== exhaustion of transient list failures"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 504 502 503 504
run_watch "$STATE"
assert_eq "$RC" "1" "exhaustion exits 1"
assert_file_count "$STATE/api.calls" "4" "1 initial + 3 retries"
assert_file_count "$STATE/workflow.calls" "0" "no dispatch after list exhaustion"
assert_contains "$ERR" "GitHub read failed after 4 attempts" "reports exhaustion"
rm -rf "$STATE"

echo "== nontransient auth failure (HTTP 401, no retry)"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 401 200
run_watch "$STATE"
assert_eq "$RC" "1" "401 exits 1"
assert_file_count "$STATE/api.calls" "1" "401 is not retried"
assert_file_count "$STATE/workflow.calls" "0" "no dispatch on 401"
assert_contains "$ERR" "non-transient error (HTTP 401)" "classifies 401 as non-transient"
rm -rf "$STATE"

echo "== nontransient permission failure (HTTP 403, no retry)"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 403 200
run_watch "$STATE"
assert_eq "$RC" "1" "403 exits 1"
assert_file_count "$STATE/api.calls" "1" "403 is not retried"
assert_file_count "$STATE/workflow.calls" "0" "no dispatch on 403"
assert_contains "$ERR" "non-transient error (HTTP 403)" "classifies 403 as non-transient"
rm -rf "$STATE"

echo "== unchanged stable release selection and single dispatch"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 200
: > "$STATE/releases"
run_watch "$STATE"
assert_eq "$RC" "0" "missing local release exits 0 after dispatch"
assert_contains "$OUT" "Latest stable upstream: rust-v0.167.0 (version 0.167.0)" "filter skips alpha/rc/beta/preview/prerelease/draft/js tags"
assert_contains "$OUT" "dispatching build.yml for 0.167.0" "dispatches selected version only"
assert_file_count "$STATE/workflow.calls" "1" "workflow run once"
assert_contains "$(cat "$STATE/workflow.calls")" "build.yml --repo sudoytang/codex-loongarch-oldworld --ref main -f version=0.167.0" "dispatch args preserved"
assert_file_count "$STATE/release.calls" "2" "checks v0.167.0 then rust-v0.167.0"
rm -rf "$STATE"

echo "== no duplicate dispatch when rust-v tag already exists"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 200
write_lines "$STATE/releases" "rust-v0.167.0"
run_watch "$STATE"
assert_eq "$RC" "0" "existing rust-v tag exits 0"
assert_file_count "$STATE/workflow.calls" "0" "does not dispatch when rust-v0.167.0 exists"
rm -rf "$STATE"

echo "== failed existing-release lookup does not dispatch"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 200
write_lines "$STATE/release.plan" 504 504 504 504
: > "$STATE/releases"
run_watch "$STATE"
assert_eq "$RC" "1" "release-view exhaustion exits 1"
assert_file_count "$STATE/workflow.calls" "0" "lookup failure is not treated as missing"
rm -rf "$STATE"

echo "== workflow dispatch is not retried"
STATE="$(mktemp -d)"
write_lines "$STATE/api.plan" 200
: > "$STATE/releases"
write_lines "$STATE/workflow.plan" 504 200
run_watch "$STATE"
assert_eq "$RC" "1" "failed dispatch exits 1"
assert_file_count "$STATE/workflow.calls" "1" "dispatch is attempted once"
rm -rf "$STATE"

echo
echo "passed=$PASS failed=$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
