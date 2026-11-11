#!/bin/bash
# Script to generate comment text for support issue triage workflow
# Usage: get-comment.sh <comment_type> [args...]

COMMENT_TYPE="$1"
shift  # Remove first argument so $@ contains remaining args

case "$COMMENT_TYPE" in
  product-triage)
    cat <<'EOF'
👋 @timrogers, please review this support issue and triage it. Please apply one of the labels below after evaluation:
1. `support-issue:known-feature-gap`: this will close the issue automatically
2. `support-issue:needs-more-info`: this will prompt the issue creator for more information from users
3. `support-issue:needs-engineering-triage`: this will @ mention current on-call to start investigation
EOF
    ;;

  product-triage-reopened)
    cat <<'EOF'
👋 @timrogers, this support issue has been re-opened. Please review and triage it. Please apply one of the labels below after evaluation:
1. `support-issue:known-feature-gap`: this will close the issue automatically
2. `support-issue:needs-more-info`: this will prompt the issue creator for more information from users
3. `support-issue:needs-engineering-triage`: this will @ mention current on-call to start investigation
EOF
    ;;

  engineering-triage)
    ONCALL_HANDLE="$1"
    # Validate oncall handle (only allow alphanumeric, dashes, and slashes)
    if ! [[ "$ONCALL_HANDLE" =~ ^[a-zA-Z0-9/-]+$ ]]; then
      ONCALL_HANDLE="github/copilot-extensibility-team"
    fi
    cat <<EOF
👋 @${ONCALL_HANDLE}, this support issue has been evaluated and requiring engineering investigation. Please review and triage.

If more info is needed, you can apply the \`support-issue:needs-more-info\` label.
EOF
    ;;

  engineering-triage-reopened)
    ONCALL_HANDLE="$1"
    # Validate oncall handle (only allow alphanumeric, dashes, and slashes)
    if ! [[ "$ONCALL_HANDLE" =~ ^[a-zA-Z0-9/-]+$ ]]; then
      ONCALL_HANDLE="github/copilot-extensibility-team"
    fi
    cat <<EOF
👋 @${ONCALL_HANDLE}, this support issue has been re-opened and requires engineering investigation. Please review and triage.

If more info is needed, you can apply the \`support-issue:needs-more-info\` label.
EOF
    ;;

  more-info)
    USERNAME="$1"
    cat <<EOF
👋 @${USERNAME}, thank you for reporting this issue. After product/engineering triage, it seems we need more information to help diagnose and address this problem.

Could you review product/engineering inputs above and provide the extra info needed?

Once extra info is provided you can apply either \`support-issue:needs-engineering-triage\` or \`support-issue:needs-product-triage\` label to re-engage.
EOF
    ;;

  feature-gap)
    echo "This issue has been closed as it represents a known feature gap. If you think this is done in error, please feel free to re-open it."
    ;;

  *)
    echo "Error: Unknown comment type '$COMMENT_TYPE'" >&2
    echo "Valid types: product-triage, product-triage-reopened, engineering-triage, engineering-triage-reopened, more-info, feature-gap" >&2
    exit 1
    ;;
esac
