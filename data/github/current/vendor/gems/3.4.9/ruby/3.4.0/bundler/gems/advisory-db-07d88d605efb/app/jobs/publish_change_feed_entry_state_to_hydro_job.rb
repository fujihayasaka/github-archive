# frozen_string_literal: true

class PublishChangeFeedEntryStateToHydroJob < ApplicationJob
  queue_as :low

  def perform(feed_entry, old_state:, new_state:)
    result = AdvisoryDB.hydro_publisher.publish(
      {
        feed_entry: feed_entry.hydro_payload,
        old_state: old_state,
        new_state: new_state,
      },
      schema: "advisory_db.v0.ChangeFeedEntryState", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
