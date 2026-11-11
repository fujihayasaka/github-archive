# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  # An abstract superclass for filters
  class BaseFilter
    def self.apply(events, viewer)
      raise NotImplementedError
    end
  end
end
