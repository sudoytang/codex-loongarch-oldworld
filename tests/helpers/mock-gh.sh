#!/bin/bash
# Mock `gh` for watch-upstream tests. Driven by GH_MOCK_STATE files; no network.
set -euo pipefail

: "${GH_MOCK_STATE:?GH_MOCK_STATE is required}"
mkdir -p "$GH_MOCK_STATE"
printf '%s\n' "$0 $*" >> "$GH_MOCK_STATE/log"

next_plan() {
  local file="$1"
  local default="${2:-}"
  if [ -s "$file" ]; then
    local code
    code="$(head -n 1 "$file")"
    tail -n +2 "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    printf '%s\n' "$code"
    return 0
  fi
  if [ -n "$default" ]; then
    printf '%s\n' "$default"
    return 0
  fi
  return 1
}

fail_http() {
  local code="$1"
  local extra="${2:-}"
  case "$code" in
    401)
      echo "gh: HTTP 401: Bad credentials (https://api.github.com/user)${extra:+ $extra}" >&2
      ;;
    403)
      echo "gh: HTTP 403: Resource not accessible by integration${extra:+ $extra}" >&2
      ;;
    404)
      echo "release not found" >&2
      echo "gh: HTTP 404: Not Found (https://api.github.com/repos/example/example/releases/tags/x)" >&2
      ;;
    422)
      echo "gh: HTTP 422: Validation Failed${extra:+ $extra}" >&2
      ;;
    500|502|503|504)
      echo "gh: We couldn't respond to your request in time. Sorry about that. Please try resubmitting your request and contact us if the problem persists. (HTTP ${code})" >&2
      ;;
    429)
      echo "gh: HTTP 429: API rate limit exceeded" >&2
      ;;
    *)
      echo "gh: mock error (HTTP ${code})${extra:+ $extra}" >&2
      ;;
  esac
  exit 1
}

cmd="${1:-}"
shift || true

case "$cmd" in
  api)
    endpoint="${1:-}"
    printf '%s\n' "$endpoint" >> "$GH_MOCK_STATE/api.calls"
    code="$(next_plan "$GH_MOCK_STATE/api.plan" "200")"
    if [ "$code" != "200" ]; then
      fail_http "$code"
    fi
    json_file="${GH_MOCK_API_JSON:-$GH_MOCK_STATE/api.json}"
    jq_prog=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --jq)
          jq_prog="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ -z "$jq_prog" ]; then
      cat "$json_file"
      exit 0
    fi
    jq -r "$jq_prog" "$json_file"
    ;;
  release)
    sub="${1:-}"
    tag="${2:-}"
    printf '%s\n' "$tag" >> "$GH_MOCK_STATE/release.calls"
    if [ "$sub" != "view" ]; then
      echo "gh: mock only implements release view" >&2
      exit 2
    fi
    if code="$(next_plan "$GH_MOCK_STATE/release.plan")"; then
      if [ "$code" != "200" ]; then
        fail_http "$code"
      fi
    fi
    if [ -f "$GH_MOCK_STATE/releases" ] && grep -Fxq "$tag" "$GH_MOCK_STATE/releases"; then
      echo "title: $tag"
      exit 0
    fi
    fail_http 404
    ;;
  workflow)
    sub="${1:-}"
    printf '%s\n' "$*" >> "$GH_MOCK_STATE/workflow.calls"
    if [ "$sub" != "run" ]; then
      echo "gh: mock only implements workflow run" >&2
      exit 2
    fi
    if code="$(next_plan "$GH_MOCK_STATE/workflow.plan")"; then
      if [ "$code" != "200" ]; then
        fail_http "$code"
      fi
    fi
    echo "https://github.com/example/example/actions"
    ;;
  *)
    echo "gh: unexpected mock command: $cmd $*" >&2
    exit 2
    ;;
esac
