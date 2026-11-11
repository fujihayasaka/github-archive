# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class SpamFilter < BaseFilter
    # Filters a list of event to exclude events created
    # by spammy users.
    #
    # events - Array of Stratocaster::Event items to filter in place.
    #
    # Returns an Array of Stratocaster::Event items
    def self.apply(events, viewer)
      events.delete_if(&:spammy_sender?)
    end
  end
end
