# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class RetentionFilter < BaseFilter
    RETENTION_PERIOD = 7.days

    # Filters a list of events to exclude events that are older than the
    # retention period and if the related feature flag is enabled.
    #
    # events - Array of Stratocaster::Event items to filter in place.
    #
    # Returns an Array of Stratocaster::Event items
    def self.apply(events, viewer)
      return events if GitHub.enterprise?
      return events unless viewer&.feature_enabled?(:stratocaster_retention_filter) ||
              GitHub.flipper[:stratocaster_retention_filter].enabled?

      events.delete_if do |event|
        event.created_at < (Time.now - RETENTION_PERIOD)
      end
    end
  end
end
