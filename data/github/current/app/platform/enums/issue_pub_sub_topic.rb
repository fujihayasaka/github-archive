# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IssuePubSubTopic < Platform::Enums::Base
      description "The possible PubSub channels for an issue."
      mobile_only true
      required_capabilities [:subscribe_alive_events]

      value "UPDATED", "The channel ID for observing issue updates.", value: "updated"
      value "TIMELINE", "The channel ID for updating items on the issue timeline.", value: "timeline"
      value "STATE", "The channel ID for observing issue state updates.", value: "state"
      value "CLOSE_REFERENCES", "The channel ID for observing issue close references.", value: "close_references"
    end
  end
end
