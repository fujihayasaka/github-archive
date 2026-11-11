# typed: true
# frozen_string_literal: true

module BusinessAiControls
  module AgentSessionMetadata
    extend ActiveSupport::Concern

    # Map raw status values to user-friendly display names
    STATUS_DISPLAY_NAMES = T.let({
      "queued" => "Queued",
      "in_progress" => "In Progress",
      "completed" => "Completed",
      "failed" => "Failed",
      "idle" => "Idle",
      "waiting_for_user" => "Waiting for User",
      "timed_out" => "Timed Out",
      "cancelled" => "Cancelled"
    }.freeze, T::Hash[String, String])

    SessionTimeframeFilter = T.type_alias do
      {
        value: String,
        number: Integer,
        display_name: String,
      }
    end
    SESSION_TIMEFRAME_FILTERS = T.let({
      twenty_four_hours: { value: "24h", number: 24, display_name: "Past 24 hours" },
      seven_days: { value: "7d", number: 7, display_name: "Past 7 days" },
    }.freeze, { twenty_four_hours: SessionTimeframeFilter, seven_days: SessionTimeframeFilter })
  end
end
