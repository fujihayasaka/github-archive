# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserPubSubTopic < Platform::Enums::Base
      description "The possible PubSub channels for a user."
      required_capabilities [:mobile_only_schema_mask, :subscribe_alive_events]

      value :NOTIFICATIONS_CHANGED, "The channel ID for observing user notifications changed updates.", value: "notifications_changed"
      value :MARKED_READ, "The channel ID for observing user marked as read updates.", value: "marked_read"
    end
  end
end
