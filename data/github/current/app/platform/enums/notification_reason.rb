# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NotificationReason < Platform::Enums::Base
      description "The reason you received a notification about a subject."
      required_capabilities [:mobile_only_schema_mask, :access_internal_graphql_notifications]

      value "ASSIGN", "You were assigned to the Issue/PR.", value: "assign"
      value "AUTHOR", "You created the thread.", value: "author"
      value "COMMENT", "You commented on the thread.", value: "comment"
      value "INVITATION", "You accepted an invitation to contribute to the repository.", value: "invitation"
      value "MANUAL", "You subscribed to the thread (via an Issue or Pull Request).", value: "manual"
      value "MENTION", "You were specifically @mentioned in the content.", value: "mention"
      value "REVIEW_REQUESTED", "You were requested for review.", value: "review_requested"
      value "SECURITY_ADVISORY_CREDIT", "You were given credit for contributing to a Security Advisory.", value: "security_advisory_credit"
      value "SECURITY_ALERT", "You have access to the notification subject's Dependabot alerts.", value: "security_alert"
      value "STATE_CHANGE", "You changed the thread state (for example, closing an Issue or merging a Pull Request).", value: "state_change"
      value "SUBSCRIBED", "You are watching the subject of the notification.", value: "subscribed"
      value "TEAM_MENTION", "You were on a team that was mentioned.", value: "team_mention"
      value "CI_ACTIVITY", "You are subscribed to continuous integration activity.", value: "ci_activity"
      value "APPROVAL_REQUESTED", "You were requested for review for deployment.", value: "approval_requested"
      value "SAVED", "You saved this notification", value: "saved"
      value "READY_FOR_REVIEW", "A pull request you're subscribed to was marked ready for review.", value: "ready_for_review"
      value "MEMBER_FEATURE_REQUESTED", "New requests from members.", value: "member_feature_requested"
    end
  end
end
