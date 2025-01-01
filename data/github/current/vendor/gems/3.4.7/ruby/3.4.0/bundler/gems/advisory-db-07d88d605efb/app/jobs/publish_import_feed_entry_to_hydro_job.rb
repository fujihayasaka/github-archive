# frozen_string_literal: true

class PublishImportFeedEntryToHydroJob < ApplicationJob
  queue_as :low

  def perform(feed_entry, created:)
    result = AdvisoryDB.hydro_publisher.publish(
      {
        feed_entry: feed_entry.hydro_payload,
        action: created ? :CREATE : :UPDATE,
      },
      schema: "advisory_db.v0.ImportFeedEntry", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    AdvisoryDB.send_hydro_publish_error_stat(self.class) unless result.success?

    result
  end
end
