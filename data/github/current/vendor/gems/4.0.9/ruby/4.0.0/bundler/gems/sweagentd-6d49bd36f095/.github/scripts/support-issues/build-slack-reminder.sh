#!/bin/bash
# Build a Slack message summarizing open support escalation issues
# that still need triage attention, grouped by severity.
#
# Required env vars:
#   GITHUB_TOKEN       - GitHub token for API access
#   GITHUB_REPOSITORY  - owner/repo
#   GITHUB_OUTPUT      - Actions output file
#
# Optional env vars:
#   ONCALL_HANDLE      - Current on-call engineer's GitHub handle (from PagerDuty); if unset, falls back to team mention
#   SLACK_TOKEN        - Slack bot API token; enables resolving emails to Slack <@USERID> mentions
#   SUPPRESS_MENTIONS  - If "true", do not include Slack mentions in the output (default: false)
#   REPAIR_DRY_RUN     - If "true", wrap repair-section mentions in backticks so they appear in the list but do not ping (default: false)
#
# Outputs (via GITHUB_OUTPUT):
#   has_issues - "true" if there are issues to report, "false" otherwise
#   message    - The formatted Slack message

set -euo pipefail

# --- Function definitions (must precede first call) ---

# Resolve an email address to a Slack <@USERID> mention using users.lookupByEmail.
# Returns the mention on success, empty string on failure.
resolve_slack_mention_from_email() {
  local email="$1"

  if [ -z "$email" ] || [ "$email" = "null" ] || [ -z "$SLACK_TOKEN" ]; then
    return
  fi

  local encoded_email
  encoded_email=$(printf '%s' "$email" | jq -sRr @uri)

  local response
  response=$(curl -s -X GET \
    --connect-timeout 5 --max-time 15 \
    "https://slack.com/api/users.lookupByEmail?email=${encoded_email}" \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H "Accept: application/json" 2>/dev/null || true)

  local user_id
  user_id=$(echo "$response" | jq -r 'select(.ok == true) | .user.id // empty' 2>/dev/null || true)

  if [ -n "$user_id" ]; then
    echo "<@${user_id}>"
  fi
}

# Resolve a GitHub login to a Slack mention by looking up <login>@github.com.
# Falls back to @login if resolution fails.
resolve_github_mention() {
  local login="$1"

  if [ -n "$SLACK_TOKEN" ]; then
    local github_email
    github_email="${login,,}@github.com"
    local mention
    mention=$(resolve_slack_mention_from_email "$github_email")
    if [ -n "$mention" ]; then
      echo "$mention"
      return
    fi
  fi

  echo "@${login}"
}

# --- Variable initialization ---

ONCALL_HANDLE="${ONCALL_HANDLE:-}"
VALIDATED_ONCALL_HANDLE=""
if [[ "$ONCALL_HANDLE" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  VALIDATED_ONCALL_HANDLE="$ONCALL_HANDLE"
fi
REPO="${GITHUB_REPOSITORY:-}"
SUPPRESS_MENTIONS="${SUPPRESS_MENTIONS:-false}"
REPAIR_DRY_RUN="${REPAIR_DRY_RUN:-false}"
SLACK_TOKEN="${SLACK_TOKEN:-}"
PRODUCT_CONTACT="timrogers"
REPAIR_FALLBACK_HANDLE="shakingbeef"

if [ -z "$REPO" ]; then
  echo "Error: GITHUB_REPOSITORY is required" >&2
  exit 1
fi

PRODUCT_MENTION="$(resolve_github_mention "$PRODUCT_CONTACT")"

if [ -n "$VALIDATED_ONCALL_HANDLE" ]; then
  ONCALL_MENTION="$(resolve_github_mention "$VALIDATED_ONCALL_HANDLE")"
else
  ONCALL_MENTION="@github/coding-agent-core-team"
fi

# Fetch all open issues with support-escalation label
ISSUES=$(gh issue list \
  --repo "$REPO" \
  --label "support-escalation" \
  --state open \
  --json number,title,labels,url,assignees \
  --limit 200)

# Filter out issues that have known-feature-gap or needs-more-info labels
# (these are considered handled and should not appear in the daily reminder)
ISSUES=$(echo "$ISSUES" | jq '[.[] | select(
  (.labels | map(.name) | index("support-issue:known-feature-gap") | not) and
  (.labels | map(.name) | index("support-issue:needs-more-info") | not)
)]')

ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')

# Build a single issue line with triage owner mention.
# Returns an empty string (skip) when the issue should not be surfaced / mentioned.
build_issue_line() {
  local number="$1"
  local title="$2"
  local url="$3"
  local labels_json="$4"
  local assignees_json="$5"

  local mention=""
  local triage_type=""

  local assignee_count
  assignee_count=$(echo "$assignees_json" | jq 'length')

  if [ "$assignee_count" -gt 0 ]; then
    # Issue is assigned — skip label-based logic.
    # Only surface assigned issues that have gone stale.
    if echo "$labels_json" | jq -e 'map(.name) | index("stale")' > /dev/null 2>&1; then
      mention=""
      local resolved
      while IFS= read -r login; do
        resolved=$(resolve_github_mention "$login")
        mention="${mention:+${mention} }${resolved}"
      done < <(echo "$assignees_json" | jq -r '.[].login')
      triage_type="stale — assigned"
    else
      echo ""
      return
    fi
  else
    # No assignee — use label-based logic
    local has_product_triage=false
    local has_eng_triage=false
    if echo "$labels_json" | jq -e 'map(.name) | index("support-issue:needs-product-triage")' > /dev/null 2>&1; then
      has_product_triage=true
    fi
    if echo "$labels_json" | jq -e 'map(.name) | index("support-issue:needs-engineering-triage")' > /dev/null 2>&1; then
      has_eng_triage=true
    fi

    local eng_mention=""
    if [ "$has_eng_triage" = true ]; then
      eng_mention="$ONCALL_MENTION"
    fi

    if [ "$has_product_triage" = true ] && [ "$has_eng_triage" = true ]; then
      mention="${PRODUCT_MENTION} ${eng_mention}"
      triage_type="needs product & engineering triage"
    elif [ "$has_product_triage" = true ]; then
      mention="$PRODUCT_MENTION"
      triage_type="needs product triage"
    elif [ "$has_eng_triage" = true ]; then
      mention="$eng_mention"
      triage_type="needs engineering triage"
    else
      mention="$ONCALL_MENTION"
      triage_type="needs triage"
    fi
  fi

  # No mention determined — caller will exclude this issue
  if [ -z "$mention" ]; then
    echo ""
    return
  fi

  local line="• <${url}|#${number}> ${title}"
  if [ "$SUPPRESS_MENTIONS" != "true" ]; then
    line="${line} — ${mention} (${triage_type})"
  else
    line="${line} — (${triage_type})"
  fi

  echo "$line"
}

# Group issues by severity (prioritize highest: SEV1 > SEV2 > SEV3)
SEV1_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(.labels | map(.name) | index("support-sev1"))]')
SEV2_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(
  (.labels | map(.name) | index("support-sev2")) and
  (.labels | map(.name) | index("support-sev1") | not)
)]')
SEV3_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(
  (.labels | map(.name) | index("support-sev3")) and
  (.labels | map(.name) | index("support-sev1") | not) and
  (.labels | map(.name) | index("support-sev2") | not)
)]')
UNLABELED_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(
  (.labels | map(.name) | index("support-sev1") | not) and
  (.labels | map(.name) | index("support-sev2") | not) and
  (.labels | map(.name) | index("support-sev3") | not)
)]')

# Build the Slack message (mrkdwn format)
MESSAGE="🔔 *Daily Support Escalation Reminder*"$'\n'

TOTAL_INCLUDED=0

append_section() {
  local section_name="$1"
  local issues_json="$2"
  local count
  count=$(echo "$issues_json" | jq 'length')

  if [ "$count" -eq 0 ]; then
    return
  fi

  local section_lines=""
  local included_count=0

  while IFS= read -r issue; do
    local number title url labels assignees line
    number=$(echo "$issue" | jq -r '.number')
    title=$(echo "$issue" | jq -r '.title')
    url=$(echo "$issue" | jq -r '.url')
    labels=$(echo "$issue" | jq -c '.labels')
    assignees=$(echo "$issue" | jq -c '.assignees')

    line=$(build_issue_line "$number" "$title" "$url" "$labels" "$assignees")
    if [ -n "$line" ]; then
      section_lines="${section_lines}${line}"$'\n'
      included_count=$((included_count + 1))
    fi
  done < <(echo "$issues_json" | jq -c '.[]')

  if [ "$included_count" -eq 0 ]; then
    return
  fi

  TOTAL_INCLUDED=$((TOTAL_INCLUDED + included_count))
  MESSAGE="${MESSAGE}"$'\n'"*${section_name}* (${included_count}):"$'\n'
  MESSAGE="${MESSAGE}${section_lines}"
}

append_section "🔴 SEV1" "$SEV1_ISSUES"
append_section "🟡 SEV2" "$SEV2_ISSUES"
append_section "⚪ SEV3" "$SEV3_ISSUES"
append_section "⚠️ Unclassified" "$UNLABELED_ISSUES"

# --- Incident repair items ---
# Repair items are open issues labeled "incident-repair", with SLAs based on sub-label:
#   - "incident-repair-short-term": 7 days
#   - "incident-repair-long-term":  30 days
# Only items past their SLA are surfaced in the reminder.
REPAIR_ISSUES=$(gh issue list \
  --repo "$REPO" \
  --label "incident-repair" \
  --state open \
  --json number,title,labels,url,assignees,createdAt \
  --limit 200)

build_repair_line() {
  local number="$1"
  local title="$2"
  local url="$3"
  local labels_json="$4"
  local assignees_json="$5"
  local created_at="$6"

  local sla_days=0
  local sla_label=""
  if echo "$labels_json" | jq -e 'map(.name) | index("incident-repair-short-term")' > /dev/null 2>&1; then
    sla_days=7
    sla_label="short-term"
  elif echo "$labels_json" | jq -e 'map(.name) | index("incident-repair-long-term")' > /dev/null 2>&1; then
    sla_days=30
    sla_label="long-term"
  else
    echo ""
    return
  fi

  local created_epoch now_epoch age_days
  created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo 0)
  now_epoch=$(date +%s)
  if [ "$created_epoch" -eq 0 ]; then
    echo ""
    return
  fi
  age_days=$(( (now_epoch - created_epoch) / 86400 ))

  if [ "$age_days" -lt "$sla_days" ]; then
    echo ""
    return
  fi

  local mention=""
  local assignee_count
  assignee_count=$(echo "$assignees_json" | jq 'length')
  if [ "$assignee_count" -gt 0 ]; then
    local resolved
    while IFS= read -r login; do
      resolved=$(resolve_github_mention "$login")
      mention="${mention:+${mention} }${resolved}"
    done < <(echo "$assignees_json" | jq -r '.[].login')
  else
    mention=$(resolve_github_mention "$REPAIR_FALLBACK_HANDLE")
  fi

  local overdue_by=$(( age_days - sla_days ))
  local line="• <${url}|#${number}> ${title}"
  if [ "$SUPPRESS_MENTIONS" != "true" ]; then
    local display_mention="$mention"
    if [ "$REPAIR_DRY_RUN" = "true" ]; then
      display_mention="\`${mention}\`"
    fi
    line="${line} — ${display_mention} (${sla_label} SLA, ${age_days}d old, overdue by ${overdue_by}d)"
  else
    line="${line} — (${sla_label} SLA, ${age_days}d old, overdue by ${overdue_by}d)"
  fi
  echo "$line"
}

REPAIR_SECTION_LINES=""
REPAIR_INCLUDED=0
while IFS= read -r issue; do
  [ -z "$issue" ] && continue
  number=$(echo "$issue" | jq -r '.number')
  title=$(echo "$issue" | jq -r '.title')
  url=$(echo "$issue" | jq -r '.url')
  labels=$(echo "$issue" | jq -c '.labels')
  assignees=$(echo "$issue" | jq -c '.assignees')
  created_at=$(echo "$issue" | jq -r '.createdAt')

  line=$(build_repair_line "$number" "$title" "$url" "$labels" "$assignees" "$created_at")
  if [ -n "$line" ]; then
    REPAIR_SECTION_LINES="${REPAIR_SECTION_LINES}${line}"$'\n'
    REPAIR_INCLUDED=$((REPAIR_INCLUDED + 1))
  fi
done < <(echo "$REPAIR_ISSUES" | jq -c '.[]')

if [ "$REPAIR_INCLUDED" -gt 0 ]; then
  TOTAL_INCLUDED=$((TOTAL_INCLUDED + REPAIR_INCLUDED))
  MESSAGE="${MESSAGE}"$'\n'"*🛠️ Incident Repair (overdue)* (${REPAIR_INCLUDED}):"$'\n'
  MESSAGE="${MESSAGE}${REPAIR_SECTION_LINES}"
fi

if [ "$TOTAL_INCLUDED" -eq 0 ]; then
  echo "has_issues=false" >> "$GITHUB_OUTPUT"
  echo "No mentionable support escalation issues after filtering."
  exit 0
fi

echo "has_issues=true" >> "$GITHUB_OUTPUT"

MESSAGE="${MESSAGE}"$'\n'"💡 _Tip: Apply \`support-issue:known-feature-gap\` or \`support-issue:needs-more-info\` after triage to stop the daily reminder for an issue._"

# Write multiline output using heredoc delimiter
{
  echo "message<<SLACKEOF"
  echo "$MESSAGE"
  echo "SLACKEOF"
} >> "$GITHUB_OUTPUT"

echo "Built reminder for ${TOTAL_INCLUDED} issue(s) (${ISSUE_COUNT} open, $((ISSUE_COUNT - TOTAL_INCLUDED)) excluded)."
