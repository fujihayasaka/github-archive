#!/usr/bin/env bash
# run-parallel.sh — Run all IPM QA tests locally in parallel batches.
#
# Usage:
#   bash script/in-product-messaging/qa/run-parallel.sh [--parallel N] [--domain URL] [--test name1,name2,...] [--multiples N] [--no-multiples]
#
# Dynamically reads the .md test files in this directory to build the test
# list, so adding/removing a test .md file is all that's needed.
#
# --test accepts a comma-separated list of test names (with or without the
# `.md` extension). Only matching tests are run. Useful for retrying a
# subset after a fix without re-running the whole suite. Examples:
#   --test 10-dashboard-cli
#   --test 10-dashboard-cli,17-nav-ent-new-tasks
#
# --multiples N  Maximum number of suffixed user copies available (default: 5).
#                Must match the N passed to `setup --multiples N`.
# --no-multiples Disable the automatic suffix-bumping behavior.
# --reset-multiples  Reset state back to base usernames (no suffix).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARALLEL=8
DOMAIN="http://github.localhost"
TEST_FILTER=""
MULTIPLES_MAX=5
MULTIPLES_DISABLED=false
MULTIPLES_RESET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --parallel)        PARALLEL="$2"; shift 2 ;;
    --domain)          DOMAIN="$2";   shift 2 ;;
    --test)            TEST_FILTER="$2"; shift 2 ;;
    --multiples)       MULTIPLES_MAX="$2"; shift 2 ;;
    --no-multiples)    MULTIPLES_DISABLED=true; shift ;;
    --reset-multiples) MULTIPLES_RESET=true; shift ;;
    *)                 shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Multiples state — track which user suffix to use across runs
# ---------------------------------------------------------------------------
# On the first run, we use the base usernames (no suffix). If that run has
# failures and you re-run, we bump to suffix -0, then -1, etc. This avoids
# needing to re-run script/in-product-messaging/setup between iterations.
STATE_FILE="/tmp/ipm-qa-multiples-state"

if [ "$MULTIPLES_RESET" = "true" ]; then
  rm -f "$STATE_FILE"
  echo "🔄 Multiples state reset — will use base usernames"
fi

if [ "$MULTIPLES_DISABLED" = "true" ]; then
  SUFFIX=""
  SUFFIX_INDEX=-1
  echo "ℹ️  Multiples disabled — using base usernames"
else
  # Read the current suffix index from state file, or start fresh (-1 = no suffix)
  if [ -f "$STATE_FILE" ]; then
    SUFFIX_INDEX=$(cat "$STATE_FILE")
  else
    SUFFIX_INDEX=-1
  fi

  if [ "$SUFFIX_INDEX" -lt 0 ]; then
    SUFFIX=""
    echo "ℹ️  Multiples: first run — using base usernames"
  else
    if [ "$SUFFIX_INDEX" -ge "$MULTIPLES_MAX" ]; then
      echo "⚠️  Multiples exhausted ($MULTIPLES_MAX copies used). Wrapping to -0."
      echo "   Run with --reset-multiples to start fresh, or re-run setup with --multiples $MULTIPLES_MAX"
      SUFFIX_INDEX=0
    fi
    SUFFIX="-${SUFFIX_INDEX}"
    echo "ℹ️  Multiples: using suffix '${SUFFIX}' (run $((SUFFIX_INDEX + 1)) of $MULTIPLES_MAX)"
  fi
fi

# Build a space-padded list of allowed test names (with a sentinel space at
# each end) so we can match with a glob pattern. bash 3.2 (the macOS default)
# doesn't support `declare -A`, so we avoid associative arrays here.
FILTER_LIST=""
if [ -n "$TEST_FILTER" ]; then
  IFS=',' read -ra FILTER_NAMES <<< "$TEST_FILTER"
  for name in "${FILTER_NAMES[@]}"; do
    # Trim whitespace and strip a trailing `.md` so users can pass either form.
    name="$(echo "$name" | sed 's/^ *//;s/ *$//')"
    name="${name%.md}"
    [ -n "$name" ] && FILTER_LIST="$FILTER_LIST $name"
  done
  FILTER_LIST="$FILTER_LIST "
fi

filter_includes() {
  # Returns 0 if the test name is in the filter list (or no filter is set).
  if [ -z "$FILTER_LIST" ]; then
    return 0
  fi
  case "$FILTER_LIST" in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Ensure Playwright is available
# ---------------------------------------------------------------------------
PW_DIR="$HOME/.cache/copilot-qa-playwright"
if [ ! -d "$PW_DIR/node_modules/playwright" ]; then
  echo "[setup] Installing Playwright..."
  mkdir -p "$PW_DIR"
  (cd "$PW_DIR" && npm init -y --silent 2>/dev/null && npm install playwright --silent 2>&1)
  (cd "$PW_DIR" && npx playwright install chromium 2>&1)
fi

# ---------------------------------------------------------------------------
# Create temp work directory
# ---------------------------------------------------------------------------
WORK_DIR=$(mktemp -d "/tmp/ipm-qa-XXXXXX")
echo "Work directory: $WORK_DIR"

# ---------------------------------------------------------------------------
# Parse .md test files and build the test list
# ---------------------------------------------------------------------------
parse_field() {
  # Extracts a markdown table field value from a test .md file
  # Usage: parse_field <file> <field_name>
  grep -i "| *\*\*$2\*\*" "$1" 2>/dev/null | awk -F'|' '{print $3}' | sed 's/^ *"//;s/" *$//;s/^ *`//;s/` *$//;s/^ *//;s/ *$//' | head -1
}

TESTS=()
TEST_NAMES=()

for md_file in "$SCRIPT_DIR"/[0-9][0-9]-*.md; do
  [ -f "$md_file" ] || continue
  filename=$(basename "$md_file" .md)

  # If --test was passed, skip any test whose filename isn't in the filter list.
  if ! filter_includes "$filename"; then
    continue
  fi

  cta_login=$(parse_field "$md_file" "CTA Login")
  [ -z "$cta_login" ] && continue

  # Skip tests marked with Skip: true
  skip_field=$(parse_field "$md_file" "Skip")
  if [ "$skip_field" = "true" ]; then
    echo "⏭️  Skipping: $filename (marked as skip)"
    continue
  fi

  # Determine test type by checking for Script field or known patterns
  script_field=$(parse_field "$md_file" "Script")
  indicator_endpoint=$(parse_field "$md_file" "Indicator Endpoint")

  if echo "$script_field" | grep -q "notification-test"; then
    # Notification test
    test_page=$(parse_field "$md_file" "Test Page")
    section_text=$(parse_field "$md_file" "Section Text")
    toggle_type=$(parse_field "$md_file" "Toggle Type")
    toggle_type=$(echo "$toggle_type" | sed 's/ .*//' | tr -d '`')
    section_text_env=$(echo "$section_text" | sed 's/ /_/g')

    script_src="$SCRIPT_DIR/notification-test.mjs"
    env_vars="CTA_LOGIN=$cta_login TEST_PAGE=$test_page SECTION_TEXT=$section_text_env TOGGLE_TYPE=$toggle_type NUDGE_NAME=$filename"

  elif echo "$script_field" | grep -q "modal-test"; then
    # Modal test (CCA onboarding modal). Modal Login defaults to CTA Login when
    # not separately specified — `.md` files set both to the same value so the
    # `[ -z "$cta_login" ] && continue` guard above still passes.
    modal_login=$(parse_field "$md_file" "Modal Login")
    [ -z "$modal_login" ] && modal_login="$cta_login"
    test_page=$(parse_field "$md_file" "Test Page")
    modal_mode=$(parse_field "$md_file" "Modal Mode")
    expected_destination=$(parse_field "$md_file" "Expected Destination")

    script_src="$SCRIPT_DIR/modal-test.mjs"
    env_vars="MODAL_LOGIN=$modal_login TEST_PAGE=$test_page MODAL_MODE=$modal_mode NUDGE_NAME=$filename"
    if [ -n "$expected_destination" ]; then
      env_vars="$env_vars EXPECTED_DESTINATION=$expected_destination"
    fi

  elif [ -n "$indicator_endpoint" ]; then
    # Indicator test
    expected_fields=$(parse_field "$md_file" "Expected Fields")
    script_src="$SCRIPT_DIR/indicator-test.mjs"
    env_vars="CTA_LOGIN=$cta_login INDICATOR_ENDPOINT=$indicator_endpoint EXPECTED_FIELDS=$expected_fields NUDGE_NAME=$filename"

  else
    # Nudge test (default)
    dismiss_login=$(parse_field "$md_file" "Dismiss Login")
    test_page=$(parse_field "$md_file" "Test Page" | head -1)
    dismiss_test_page=$(parse_field "$md_file" "Test Page (Dismiss)")
    expected_cta=$(parse_field "$md_file" "Expected CTA" | sed 's/^"//;s/"$//' | sed 's/ /_/g')

    # Determine dismiss type
    dismiss_type="standard"
    if grep -qi "dismiss-and-redirect" "$md_file"; then
      dismiss_type="dismiss-and-redirect"
    fi

    # Handle Test Page (CTA) variant
    cta_test_page=$(parse_field "$md_file" "Test Page (CTA)")
    if [ -n "$cta_test_page" ]; then
      test_page="$cta_test_page"
    fi

    script_src="$SCRIPT_DIR/nudge-test.mjs"
    env_vars="CTA_LOGIN=$cta_login DISMISS_LOGIN=$dismiss_login TEST_PAGE=$test_page EXPECTED_CTA=$expected_cta DISMISS_TYPE=$dismiss_type NUDGE_NAME=$filename"

    if [ -n "$dismiss_test_page" ]; then
      env_vars="$env_vars DISMISS_TEST_PAGE=$dismiss_test_page"
    fi

    # Parse expected destination (supports {slug} placeholders)
    expected_destination=$(parse_field "$md_file" "Expected Destination")
    if [ -n "$expected_destination" ]; then
      env_vars="$env_vars EXPECTED_DESTINATION=$expected_destination"
    fi
  fi

  # Create per-test work directory
  test_dir="$WORK_DIR/$filename"
  mkdir -p "$test_dir/screenshots" "$test_dir/videos"
  ln -sf "$PW_DIR/node_modules" "$test_dir/node_modules"
  cp "$script_src" "$test_dir/script.mjs"

  # Apply multiples suffix to all login env vars (CTA_LOGIN, DISMISS_LOGIN, MODAL_LOGIN)
  # Mirrors the truncation logic in setup: truncate base login so total <= 39 chars.
  if [ -n "$SUFFIX" ]; then
    MAX_LOGIN=39
    suffix_len=${#SUFFIX}
    new_env_vars=""
    for pair in $env_vars; do
      key="${pair%%=*}"
      val="${pair#*=}"
      if [[ "$key" == "CTA_LOGIN" || "$key" == "DISMISS_LOGIN" || "$key" == "MODAL_LOGIN" ]]; then
        max_base=$((MAX_LOGIN - suffix_len))
        if [ ${#val} -gt $max_base ]; then
          val="${val:0:$max_base}"
        fi
        new_env_vars+="${key}=${val}${SUFFIX} "
      else
        new_env_vars+="${pair} "
      fi
    done
    env_vars="${new_env_vars% }"
  fi

  TESTS+=("$filename|$env_vars")
  TEST_NAMES+=("$filename")
done

TOTAL=${#TESTS[@]}

if [ $TOTAL -eq 0 ]; then
  if [ -n "$TEST_FILTER" ]; then
    echo "❌ No tests matched --test filter: $TEST_FILTER" >&2
    echo "   Available tests:" >&2
    for md_file in "$SCRIPT_DIR"/[0-9][0-9]-*.md; do
      [ -f "$md_file" ] && echo "     - $(basename "$md_file" .md)" >&2
    done
  else
    echo "❌ No tests found." >&2
  fi
  exit 2
fi

echo ""
echo "▶ Running $TOTAL tests, $PARALLEL at a time (local, headless)"
echo ""

# ---------------------------------------------------------------------------
# Run in parallel batches
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
FAIL_NAMES=""
BATCH_START=0

while [ $BATCH_START -lt $TOTAL ]; do
  BATCH_END=$((BATCH_START + PARALLEL))
  if [ $BATCH_END -gt $TOTAL ]; then
    BATCH_END=$TOTAL
  fi

  echo "--- Batch: tests $((BATCH_START + 1)) to $BATCH_END of $TOTAL ---"
  PIDS=()
  BNAMES=()

  for i in $(seq $BATCH_START $((BATCH_END - 1))); do
    TEST_SPEC="${TESTS[$i]}"
    TEST_NAME="${TEST_SPEC%%|*}"
    ENV_VARS="${TEST_SPEC#*|}"

    TEST_DIR="$WORK_DIR/$TEST_NAME"
    echo "  Starting: $TEST_NAME"

    env HEADLESS=true \
        SCREENSHOTS_DIR="$TEST_DIR/screenshots" \
        VIDEOS_DIR="$TEST_DIR/videos" \
        $ENV_VARS \
        node "$TEST_DIR/script.mjs" \
        > "$TEST_DIR/stdout.txt" 2> "$TEST_DIR/stderr.txt" &

    PIDS+=($!)
    BNAMES+=("$TEST_NAME")
  done

  for j in "${!PIDS[@]}"; do
    PID="${PIDS[$j]}"
    NAME="${BNAMES[$j]}"
    wait "$PID" 2>/dev/null
    EXIT_CODE=$?
    # Check destination validation result
    DEST_STATUS=""
    if grep -q "CTA DESTINATION" "$WORK_DIR/$NAME/stdout.txt" 2>/dev/null; then
      if grep -q "✅ CTA DESTINATION" "$WORK_DIR/$NAME/stdout.txt" 2>/dev/null; then
        DEST_STATUS=" [Dest ✅]"
      elif grep -q "❌ CTA DESTINATION" "$WORK_DIR/$NAME/stdout.txt" 2>/dev/null; then
        DEST_STATUS=" [Dest ❌]"
      elif grep -q "⚠️ CTA DESTINATION" "$WORK_DIR/$NAME/stdout.txt" 2>/dev/null; then
        DEST_STATUS=" [Dest ⚠️]"
      fi
    fi
    if [ $EXIT_CODE -eq 0 ] && grep -q '"success":true' "$WORK_DIR/$NAME/stdout.txt" 2>/dev/null; then
      echo "  ✅ $NAME$DEST_STATUS"
      PASS=$((PASS + 1))
    else
      echo "  ❌ $NAME (exit $EXIT_CODE)$DEST_STATUS"
      FAIL=$((FAIL + 1))
      FAIL_NAMES="$FAIL_NAMES $NAME"
    fi
  done
  echo ""

  BATCH_START=$BATCH_END
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== Results: $PASS passed, $FAIL failed out of $TOTAL tests ==="
if [ $FAIL -gt 0 ]; then
  echo "Failed:$FAIL_NAMES"
fi
echo ""
echo "Work directory: $WORK_DIR"
echo "Screenshots:    $WORK_DIR/*/screenshots/"
echo "Videos:         $WORK_DIR/*/videos/"

# ---------------------------------------------------------------------------
# Bump multiples state for next run
# ---------------------------------------------------------------------------
if [ "$MULTIPLES_DISABLED" != "true" ]; then
  if [ $FAIL -gt 0 ]; then
    NEXT_INDEX=$((SUFFIX_INDEX + 1))
    echo "$NEXT_INDEX" > "$STATE_FILE"
    if [ "$NEXT_INDEX" -lt "$MULTIPLES_MAX" ]; then
      echo ""
      echo "💡 Next run will use suffix '-${NEXT_INDEX}' (fresh user copies)."
      echo "   No need to re-run setup. Just fix your code and run again."
    else
      echo ""
      echo "⚠️  All $MULTIPLES_MAX user copies exhausted. Next run wraps to '-0'."
      echo "   Re-run: script/in-product-messaging/setup --multiples $MULTIPLES_MAX"
    fi
  else
    # All passed — reset state so next run starts fresh
    rm -f "$STATE_FILE"
  fi
fi
