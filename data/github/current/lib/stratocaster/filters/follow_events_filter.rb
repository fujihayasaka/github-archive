# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class FollowEventsFilter < BaseFilter
    def self.apply(events, _viewer)
      events.delete_if(&:follow_event?)
    end
  end
end
