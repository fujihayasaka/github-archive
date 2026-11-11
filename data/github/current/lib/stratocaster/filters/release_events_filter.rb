# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class ReleaseEventsFilter < BaseFilter
    # From `release_targets_include_author_followers` feature flag history
    FILTER_START_TIME = Time.parse("2021-04-16T17:20:00Z")
    FILTER_END_TIME = Time.parse("2021-04-16T21:10:00Z")

    def self.apply(events, viewer)
      return events if GitHub.enterprise?

      events.delete_if do |event|
        event.release_event? &&
          event.created_at.between?(FILTER_START_TIME, FILTER_END_TIME) &&
          !event.repo_record&.public?
      end
    end
  end
end
