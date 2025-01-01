# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class LabeledEventsFilter < BaseFilter
    def self.apply(events, _viewer)
      events.delete_if(&:has_labeled_action?)
    end
  end
end
