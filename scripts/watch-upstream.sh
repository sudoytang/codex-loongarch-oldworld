#!/bin/bash
# Find the latest stable openai/codex rust-vX.Y.Z release and dispatch
# build.yml if this repository does not already have a matching Release.
#
# Read calls (list upstream releases, check existing local tags) retry on
# transient GitHub/network failures. Workflow dispatch is not retried.
set -euo pipefail

: "${REPO:?REPO is required (owner/name)}"
: "${GH:=gh}"

# 1 initial attempt + WATCH_RETRY_MAX extra tries. Default: 3 retries.
WATCH_RETRY_MAX="${WATCH_RETRY_MAX:-3}"
# Base backoff in seconds; doubles after each retry (2s, 4s, 8s). Tests may set 0.
WATCH_RETRY_BASE_SECONDS="${WATCH_RETRY_BASE_SECONDS:-2}"

# Same stable-version filter as the original inline watcher.
STABLE_RUST_TAG_JQ='
  [.[]
    | select(.draft == false and .prerelease == false)
    | select((.tag_name | ascii_downcase) | (contains("alpha") or contains("beta") or contains("rc") or contains("preview")) | not)
    | select(.tag_name | test("^rust-v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    | .tag_name
  ][0] // empty
'

http_status_from_err() {
  local err="$1"
  if [[ "$err" =~ HTTP[[:space:]]+([0-9]{3}) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo ""
}

is_transient_read_error() {
  local status="$1"
  local err="$2"
  case "$status" in
    408|429|500|502|503|504) return 0 ;;
  esac
  # Transport failures often have no HTTP status.
  if [ -z "$status" ] && grep -qiE \
    'timeout|timed out|try resubmitting|connection reset|connection refused|temporarily unavailable|EOF|network is unreachable' \
    <<<"$err"; then
    return 0
  fi
  return 1
}

is_nontransient_read_error() {
  local status="$1"
  local err="$2"
  case "$status" in
    400|401|403|404|422) return 0 ;;
  esac
  if grep -qiE 'bad credentials|must have .* permission|resource not accessible|forbidden|unauthorized|validation failed' \
    <<<"$err"; then
    return 0
  fi
  return 1
}

is_missing_release_err() {
  local status="$1"
  local err="$2"
  [ "$status" = "404" ] && return 0
  grep -qi 'release not found' <<<"$err"
}

retry_sleep() {
  local delay="$1"
  if [ "$delay" -gt 0 ]; then
    sleep "$delay"
  fi
}

# Run a read-only `gh` command with bounded retries. Prints stdout on success.
# Does not retry permission/auth/logic errors. Exhaustion exits non-zero.
gh_read() {
  local attempt=0
  local max_attempts=$((WATCH_RETRY_MAX + 1))
  local delay="$WATCH_RETRY_BASE_SECONDS"
  local outfile errfile
  outfile="$(mktemp)"
  errfile="$(mktemp)"

  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    if "$GH" "$@" >"$outfile" 2>"$errfile"; then
      cat "$outfile"
      rm -f "$outfile" "$errfile"
      return 0
    fi
    local err status
    err="$(cat "$errfile")"
    status="$(http_status_from_err "$err")"

    if is_nontransient_read_error "$status" "$err"; then
      echo "$err" >&2
      echo "GitHub read failed with non-transient error (HTTP ${status:-unknown}); not retrying." >&2
      rm -f "$outfile" "$errfile"
      return 1
    fi

    if ! is_transient_read_error "$status" "$err"; then
      echo "$err" >&2
      echo "GitHub read failed with unexpected error (HTTP ${status:-unknown}); not retrying." >&2
      rm -f "$outfile" "$errfile"
      return 1
    fi

    echo "$err" >&2
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "GitHub read failed after ${max_attempts} attempts (HTTP ${status:-unknown})." >&2
      rm -f "$outfile" "$errfile"
      return 1
    fi
    echo "Transient GitHub read failure (HTTP ${status:-unknown}); retry ${attempt}/${WATCH_RETRY_MAX} in ${delay}s." >&2
    retry_sleep "$delay"
    delay=$((delay * 2))
  done
  rm -f "$outfile" "$errfile"
  return 1
}

# 0 = exists, 1 = definitely missing, 2 = lookup failed (do not dispatch).
release_exists() {
  local tag="$1"
  local attempt=0
  local max_attempts=$((WATCH_RETRY_MAX + 1))
  local delay="$WATCH_RETRY_BASE_SECONDS"
  local outfile errfile
  outfile="$(mktemp)"
  errfile="$(mktemp)"

  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    if "$GH" release view "$tag" --repo "$REPO" >"$outfile" 2>"$errfile"; then
      rm -f "$outfile" "$errfile"
      return 0
    fi
    local err status
    err="$(cat "$errfile")"
    status="$(http_status_from_err "$err")"

    if is_missing_release_err "$status" "$err"; then
      rm -f "$outfile" "$errfile"
      return 1
    fi

    if is_nontransient_read_error "$status" "$err"; then
      echo "$err" >&2
      echo "Failed to check release ${tag} with non-transient error (HTTP ${status:-unknown}); not retrying." >&2
      rm -f "$outfile" "$errfile"
      return 2
    fi

    if ! is_transient_read_error "$status" "$err"; then
      echo "$err" >&2
      echo "Failed to check release ${tag} (HTTP ${status:-unknown}); not retrying." >&2
      rm -f "$outfile" "$errfile"
      return 2
    fi

    echo "$err" >&2
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "Failed to check release ${tag} after ${max_attempts} attempts (HTTP ${status:-unknown})." >&2
      rm -f "$outfile" "$errfile"
      return 2
    fi
    echo "Transient GitHub read failure checking ${tag} (HTTP ${status:-unknown}); retry ${attempt}/${WATCH_RETRY_MAX} in ${delay}s." >&2
    retry_sleep "$delay"
    delay=$((delay * 2))
  done
  rm -f "$outfile" "$errfile"
  return 2
}

local_release_present() {
  local tag="$1"
  local rc=0
  release_exists "$tag" || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) exit 1 ;;
  esac
}

latest="$(
  gh_read api "repos/openai/codex/releases?per_page=50" --jq "$STABLE_RUST_TAG_JQ"
)"
if [ -z "$latest" ]; then
  echo "No stable rust-vX.Y.Z release found on openai/codex"
  exit 0
fi
ver="${latest#rust-v}"
echo "Latest stable upstream: $latest (version $ver)"

if local_release_present "v${ver}" || local_release_present "$latest"; then
  echo "This repository already has a release for $ver; not building."
  exit 0
fi

echo "No matching release here; dispatching build.yml for $ver"
# Non-idempotent: one attempt only. Duplicate protection is the release check above.
"$GH" workflow run build.yml --repo "$REPO" --ref main -f "version=$ver"
