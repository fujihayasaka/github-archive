# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class OrgFollowEventsFilter < BaseFilter
    def self.apply(events, _viewer)
      events.delete_if do |event|
        event.follow_event? && event.target_type == "Organization"
      end
    end
  end
end
