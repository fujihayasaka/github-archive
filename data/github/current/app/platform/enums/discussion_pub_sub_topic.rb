# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DiscussionPubSubTopic < Platform::Enums::Base
      description "The possible PubSub channels for an discussion."
      required_capabilities [:mobile_only_schema_mask, :subscribe_alive_events]

      value "UPDATED", "The channel ID for observing discussion updates.", value: "updated"
      value "TIMELINE", "The channel ID for updating items on the discussion timeline.", value: "timeline"
    end
  end
end
