# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("stratocaster.timeline_update") do |payload|
    message = {
      index_key: payload[:index_key],
      event_id: payload[:event_id],
      current_ref: GitHub.current_ref,
    }

    options = {
      schema: Stratocaster::TIMELINE_UPDATE_SCHEMA,
      partition_key: payload[:index_key],
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    }

    if GitHub.dynamic_lab?
      options[:topic] = Stratocaster::REVIEW_LAB_TIMELINE_TOPIC
    end

    GitHub.stratocaster.publish_to_hydro do
      publish_without_error_reporting(message, **options)
    end
  end
end
