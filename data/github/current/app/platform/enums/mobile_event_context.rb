# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileEventContext < Platform::Enums::Base
      mobile_only true
      description "Represents the different extra mobile context."

      # Notifications
      value "SAVE", "The notification was marked as saved.", value: "save"
      value "UNSAVE", "The notification was marked as unsaved.", value: "unsave"
      value "DONE", "The notification was marked as done.", value: "done"
      value "UNDONE", "The notification was marked as undone.", value: "undone"
      value "READ", "The notification was marked as read.", value: "read"
      value "UNREAD", "The notification was marked as unread.", value: "unread"
      value "SUBSCRIBE", "The notification list was subscribed to.", value: "subscribe"
      value "UNSUBSCRIBE", "The notification list was unsubscribed from.", value: "unsubscribe"
      value "FOCUSED", "The notification list is in focused mode.", value: "focused"
      value "NOT_FOCUSED", "The notification list is not in focused mode.", value: "not_focused"
      value "NOTIFICATIONS_ONBOARDING_FLOW", "The user has interacted with the notifications onboarding experience.", value: "notifications_onboarding_flow"

      # Issue/Pull filters
      value "CREATED", "The issue or pull request was created by the user.", value: "created"
      value "ASSIGNED", "The issue or pull request was assigned to the user.", value: "assigned"
      value "MENTIONED", "The issue or pull request mentioned the user.", value: "mentioned"
      value "REVIEW_REQUESTED", "The pull request requested review from the user.", value: "review_requested"
      value "CONTINUE_REVIEW", "The pull request review is ready to be continued by the user.", value: "continue_review"
      value "CLOSED", "The issue or pull request is closed.", value: "closed"
      value "OPEN", "The issue or pull request is open.", value: "open"

      # Release notes
      value "DISPLAYED", "Release notes have been displayed to a user", value: "displayed"

      # Banner
      value "DISMISSED", "A banner (release notes, feature onboarding, etc.) dismissed by a user", value: "dismissed"
      value "OPENED", "A banner (release notes, feature onboarding, etc.) has been opened by a user", value: "opened"

      # Feed
      value "TRENDING", "An action on an item that is trending", value: "trending"
      value "AWESOME", "An action on an item as part of the default Awesome Lists topic", value: "awesome"
      value "FEED", "An action on an item that is part of the user's feed", value: "feed"

      # Copilot
      value "COPILOT_UPSELL_BANNER_FLOW", "An action on the Copilot upsell flow", value: "copilot_upsell_banner_flow"
    end
  end
end
