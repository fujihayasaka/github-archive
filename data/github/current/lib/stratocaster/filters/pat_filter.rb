# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class PATFilter < BaseFilter
    # Filters a list of events based on organization Personal Access Token policy.
    #
    # events - Array of Stratocaster::Event items to filter in place.
    def self.apply(events, viewer)
      events.reject do |event|
        event.org_record ? event.org_record.legacy_personal_access_tokens_restricted? : false
      end
    end
  end
end
