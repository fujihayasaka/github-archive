# frozen_string_literal: true

# The equivalent model of VulnerabilityAlertingEvent on dotcom
class AdvisoryAlertingEvent < ApplicationRecord
  belongs_to :advisory, primary_key: "ghsa_id", foreign_key: "ghsa_id", inverse_of: :advisory_alerting_events

  def self.create_or_update_from_hydro(message)
    event = AdvisoryAlertingEvent.find_by(alerting_event_id: message[:alerting_event_id])

    # The timestamps in `message` come in the format of { seconds: 12345, nanos: 12345 }, which is the
    # serialized form of Google::Protobuf::Timestamp.  Thus, we must convert to `Time` to store
    processed_at_time = Google::Protobuf::Timestamp.new(message[:processed_at]).to_time if message[:processed_at]
    finished_at_time = Google::Protobuf::Timestamp.new(message[:finished_at]).to_time if message[:finished_at]

    # The message is an update to an existing alerting event if the alerting_event_id exists already
    if event
      event.update(
        processed_at: processed_at_time,
        finished_at: finished_at_time,
        alert_count: message[:alert_count],
        notification_count: message[:notification_count],
      )
    else
      AdvisoryAlertingEvent.create!(
        ghsa_id: message[:ghsa_id],
        alerting_event_id: message[:alerting_event_id],
        processed_at: processed_at_time,
        finished_at: finished_at_time,
        alert_count: message[:alert_count],
        notification_count: message[:notification_count],
      )
    end
  end
end
