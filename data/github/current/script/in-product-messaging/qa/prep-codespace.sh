#!/usr/bin/env bash
#
# prep-codespace.sh — pre-flight a github/github codespace for an IPM /qa run.
#
# Always start tests from a known state:
#   1. Resolve which codespace to operate on (auto-detect, flag, or env var).
#   2. Refuse to proceed if the codespace working tree is dirty.
#   3. git fetch + git pull --ff-only on the currently checked-out branch.
#   4. Re-run script/in-product-messaging/setup so notice state, welcome-modal
#      eligibility, backdated CB seats, etc. are freshly applied.
#
# Usage:
#   bash script/in-product-messaging/qa/prep-codespace.sh [--codespace NAME] [--tests name1,name2,...]
#
# Codespace resolution order:
#   1. --codespace NAME flag
#   2. IPM_CODESPACE env var
#   3. Auto-detect: the unique `Available` codespace whose repository is
#      `github/github`. If 0 or 2+ match, abort with a list of candidates.
#
# Scoped seeding:
#   When --tests <name1,name2> is passed, parse the listed test `.md` files in
#   `script/in-product-messaging/qa/` to extract their CTA / Dismiss / Modal
#   Login values, dedupe them, and pass the resulting list to
#   `script/in-product-messaging/setup --individual <users>` so only the
#   fixtures those tests need are recreated. Without --tests, the full IPM
#   suite is re-seeded.
#
# Designed to be re-run by humans before a /qa batch and (more importantly)
# invoked by the qa skill via the directive in qa/setup.md before any test
# run targeting http://github.localhost.

set -euo pipefail
IFS=$'\n\t'

# ---------- pretty printing ----------
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

log()  { printf "%s[prep-codespace]%s %s\n"  "${BOLD}"   "${RESET}" "$*" >&2; }
ok()   { printf "%s[prep-codespace]%s %s\n"  "${GREEN}"  "${RESET}" "$*" >&2; }
warn() { printf "%s[prep-codespace]%s %s\n"  "${YELLOW}" "${RESET}" "$*" >&2; }
err()  { printf "%s[prep-codespace]%s %s\n"  "${RED}"    "${RESET}" "$*" >&2; }
hint() { printf "  → %s\n" "$*" >&2; }

abort() {
  err "$1"
  shift || true
  for h in "$@"; do hint "$h"; done
  exit 1
}

# ---------- arg parsing ----------
CODESPACE_OVERRIDE=""
TESTS_FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --codespace)
      shift
      [ $# -gt 0 ] || abort "--codespace requires a NAME"
      CODESPACE_OVERRIDE="$1"
      shift
      ;;
    --codespace=*)
      CODESPACE_OVERRIDE="${1#--codespace=}"
      shift
      ;;
    --tests)
      shift
      [ $# -gt 0 ] || abort "--tests requires a comma-separated list of test names"
      TESTS_FILTER="$1"
      shift
      ;;
    --tests=*)
      TESTS_FILTER="${1#--tests=}"
      shift
      ;;
    -h|--help)
      sed -n '1,30p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 0
      ;;
    *)
      abort "Unknown argument: $1" \
        "Usage: bash script/in-product-messaging/qa/prep-codespace.sh [--codespace NAME] [--tests name1,name2,...]"
      ;;
  esac
done

# ---------- preflight: tooling ----------
command -v gh >/dev/null 2>&1 || abort "gh CLI not found." "Install with: brew install gh"
command -v jq >/dev/null 2>&1 || abort "jq not found."     "Install with: brew install jq"

# ---------- derive --individual from --tests (if provided) ----------
# When --tests was passed, parse each test's .md file for its CTA/Dismiss/Modal
# Login values so we can pass them to setup --individual <list>. setup uses
# prefix matching, so passing the CTA login also picks up its `-dismiss`
# sibling. We still include the dismiss/modal logins explicitly because not
# every test follows the prefix convention (e.g. ipm-team-welcome-modal vs
# ipm-team-welcome-modal-features in tests 31/33).
#
# Done up front (before any remote work) so bad test names fail fast.
INDIVIDUAL_LIST=""
if [ -n "${TESTS_FILTER}" ]; then
  log "Scoping IPM seed to fixtures for tests: ${TESTS_FILTER}"

  # Resolve QA test directory relative to this script.
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

  # parse_field <file> <field-name> — mirrors run-parallel.sh's parser.
  # Wrapped with `|| true` so a missing field (grep no-match) doesn't trip
  # the script's `set -o pipefail` / `set -e`.
  parse_field() {
    { grep -i "| *\*\*$2\*\*" "$1" 2>/dev/null || true; } \
      | awk -F'|' '{print $3}' \
      | sed 's/^ *"//;s/" *$//;s/^ *`//;s/` *$//;s/^ *//;s/ *$//' \
      | head -1
  }

  declare -a LOGINS=()
  declare -a MISSING=()

  # Split TESTS_FILTER on comma without affecting IFS for the rest of the script.
  OLD_IFS="$IFS"
  IFS=','
  for raw_name in ${TESTS_FILTER}; do
    name="${raw_name%.md}"
    name="${name## }"
    name="${name%% }"
    [ -z "$name" ] && continue

    test_file="${SCRIPT_DIR}/${name}.md"
    if [ ! -f "$test_file" ]; then
      MISSING+=("$name")
      continue
    fi

    for field in "CTA Login" "Dismiss Login" "Modal Login"; do
      val="$(parse_field "$test_file" "$field")"
      [ -n "$val" ] && LOGINS+=("$val")
    done
  done
  IFS="$OLD_IFS"

  if [ ${#MISSING[@]} -gt 0 ]; then
    err "Unknown test name(s): ${MISSING[*]}"
    hint "Available tests:"
    for md in "${SCRIPT_DIR}"/[0-9][0-9]-*.md; do
      [ -f "$md" ] && hint "  - $(basename "$md" .md)"
    done
    exit 1
  fi

  if [ ${#LOGINS[@]} -eq 0 ]; then
    abort "No CTA/Dismiss/Modal Login fields found in the specified test files." \
          "Check that the .md files have a header table with these fields."
  fi

  # Dedupe + sort for stable output.
  INDIVIDUAL_LIST="$(printf '%s\n' "${LOGINS[@]}" | sort -u | paste -sd, -)"
  ok "Resolved to --individual ${INDIVIDUAL_LIST}"
fi

# ---------- 1/3: resolve codespace ----------
log "${BOLD}[1/3]${RESET} Resolving codespace…"

CODESPACE_NAME=""
if [ -n "${CODESPACE_OVERRIDE}" ]; then
  CODESPACE_NAME="${CODESPACE_OVERRIDE}"
  log "Using --codespace override: ${CODESPACE_NAME}"
elif [ -n "${IPM_CODESPACE:-}" ]; then
  CODESPACE_NAME="${IPM_CODESPACE}"
  log "Using IPM_CODESPACE env var: ${CODESPACE_NAME}"
else
  log "Auto-detecting Available github/github codespace…"
  CODESPACES_JSON="$(gh codespace list --json name,state,repository 2>/dev/null || echo '[]')"
  AVAILABLE_NAMES="$(printf '%s' "${CODESPACES_JSON}" \
    | jq -r '.[] | select(.repository == "github/github" and .state == "Available") | .name')"
  AVAILABLE_COUNT="$(printf '%s' "${AVAILABLE_NAMES}" | grep -c . || true)"

  if [ "${AVAILABLE_COUNT}" -eq 0 ]; then
    ALL_GH_GH="$(printf '%s' "${CODESPACES_JSON}" \
      | jq -r '.[] | select(.repository == "github/github") | "  - \(.name) [\(.state)]"')"
    err "No Available github/github codespace found."
    if [ -n "${ALL_GH_GH}" ]; then
      hint "Existing github/github codespaces:"
      printf '%s\n' "${ALL_GH_GH}" >&2
    fi
    hint "Start one with: gh codespace create --repo github/github"
    hint "Or pass --codespace NAME if it already exists in another state."
    exit 1
  elif [ "${AVAILABLE_COUNT}" -gt 1 ]; then
    err "Multiple Available github/github codespaces — please disambiguate."
    while IFS= read -r line; do hint "${line}"; done <<<"${AVAILABLE_NAMES}"
    hint "Re-run with --codespace NAME or set IPM_CODESPACE=NAME"
    exit 1
  fi

  CODESPACE_NAME="${AVAILABLE_NAMES}"
  ok "Auto-detected codespace: ${CODESPACE_NAME}"
fi

# Confirm the codespace actually exists & sanity-check its repo. Don't trust
# user-supplied names blindly.
CS_INFO="$(gh codespace view -c "${CODESPACE_NAME}" --json name,state,repository 2>/dev/null || true)"
[ -n "${CS_INFO}" ] || abort "Codespace '${CODESPACE_NAME}' not found." "Check: gh codespace list"

CS_REPO="$(printf '%s' "${CS_INFO}" | jq -r '.repository')"
CS_STATE="$(printf '%s' "${CS_INFO}" | jq -r '.state')"

if [ "${CS_REPO}" != "github/github" ]; then
  abort "Codespace '${CODESPACE_NAME}' is for ${CS_REPO}, not github/github." \
        "Pass a --codespace NAME from a github/github codespace."
fi

if [ "${CS_STATE}" != "Available" ]; then
  warn "Codespace state is '${CS_STATE}'. Will attempt to ssh anyway (gh will start it if needed)."
fi

# ---------- 2/3: sync working tree ----------
log "${BOLD}[2/3]${RESET} Syncing working tree on ${CODESPACE_NAME}…"

# Run all the git work in a single SSH call so we don't pay round-trip cost
# per command. Use `bash -ls` (login shell) so the codespace's /etc/profile.d
# files restore GITHUB_TOKEN — without that, git fetch fails with
# "could not read Username for 'https://github.com'".
set +e
SYNC_OUTPUT="$(gh codespace ssh -c "${CODESPACE_NAME}" -- bash -ls <<'REMOTE_GIT' 2>&1
set -euo pipefail
cd /workspaces/github

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "${BRANCH}" = "HEAD" ]; then
  echo "PREP_FAIL detached HEAD — please check out a branch first."
  exit 10
fi

DIRTY="$(git status --porcelain)"
if [ -n "${DIRTY}" ]; then
  echo "PREP_FAIL Working tree is dirty:"
  echo "${DIRTY}"
  echo "Commit, stash, or discard changes before re-running."
  exit 11
fi

echo "PREP_INFO branch=${BRANCH}"
echo "PREP_INFO HEAD before pull: $(git rev-parse --short HEAD)"

git fetch origin "${BRANCH}" --quiet

# Use --ff-only so we never silently merge or rebase.
if ! git pull --ff-only origin "${BRANCH}"; then
  echo "PREP_FAIL Cannot fast-forward ${BRANCH}. Resolve divergence on the codespace and re-run."
  exit 12
fi

echo "PREP_INFO HEAD after pull:  $(git rev-parse --short HEAD)"
echo "PREP_OK"
REMOTE_GIT
)"
SYNC_RC=$?
set -e

# Surface remote output verbatim so users can see the new HEAD.
printf '%s\n' "${SYNC_OUTPUT}" >&2

if [ ${SYNC_RC} -ne 0 ] || ! printf '%s' "${SYNC_OUTPUT}" | grep -q '^PREP_OK$'; then
  # gh codespace ssh squashes remote exit codes to 1, so use the PREP_FAIL
  # marker we emitted from the remote script to pick a precise hint.
  if printf '%s' "${SYNC_OUTPUT}" | grep -q 'detached HEAD'; then
    abort "Codespace is on a detached HEAD." \
          "Check out the branch you want to test against on the codespace, then re-run."
  elif printf '%s' "${SYNC_OUTPUT}" | grep -q 'Working tree is dirty'; then
    abort "Codespace working tree is dirty." \
          "Commit/stash/discard changes on the codespace, then re-run." \
          "  gh codespace ssh -c ${CODESPACE_NAME}"
  elif printf '%s' "${SYNC_OUTPUT}" | grep -q 'Cannot fast-forward'; then
    abort "Cannot fast-forward the codespace branch." \
          "Resolve divergence on the codespace (e.g., reset/rebase manually), then re-run."
  else
    abort "Working-tree sync failed (rc=${SYNC_RC})." \
          "Inspect the output above; the SSH command may have failed before git ran."
  fi
fi

ok "Working tree synced (fast-forward only)."

# ---------- 3/3: re-seed IPM ----------
log "${BOLD}[3/3]${RESET} Re-running script/in-product-messaging/setup on ${CODESPACE_NAME}…"
if [ -n "${INDIVIDUAL_LIST}" ]; then
  log "(scoped via --individual ${INDIVIDUAL_LIST})"
else
  log "(this typically takes ~2-3 minutes when the orgs already exist)"
fi

set +e
gh codespace ssh -c "${CODESPACE_NAME}" -- bash -ls <<REMOTE_SETUP
set -euo pipefail
cd /workspaces/github
INDIVIDUAL_LIST="${INDIVIDUAL_LIST}"
if [ -n "\${INDIVIDUAL_LIST}" ]; then
  PATH=/workspaces/github/bin:\$PATH script/in-product-messaging/setup --multiples 5 --individual "\${INDIVIDUAL_LIST}"
else
  PATH=/workspaces/github/bin:\$PATH script/in-product-messaging/setup --multiples 5
fi
REMOTE_SETUP
SETUP_RC=$?
set -e

if [ ${SETUP_RC} -ne 0 ]; then
  abort "IPM setup script failed (rc=${SETUP_RC})." \
        "Re-run prep-codespace.sh after fixing the seed-script error." \
        "If the failure looks transient, inspect logs in the codespace:" \
        "  gh codespace ssh -c ${CODESPACE_NAME}"
fi

ok "IPM seed complete."
ok "Codespace ${CODESPACE_NAME} is ready for /qa."
