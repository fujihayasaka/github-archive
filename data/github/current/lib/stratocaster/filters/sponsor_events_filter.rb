# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class SponsorEventsFilter < BaseFilter
    def self.apply(events, _viewer)
      events.delete_if(&:sponsor_event?)
    end
  end
end
