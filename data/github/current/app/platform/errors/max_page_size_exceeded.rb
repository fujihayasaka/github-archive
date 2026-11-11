# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    # Internal: Thrown when a schema contributor tries to define a connection requesting too many records.
    class MaxPageSizeExceeded < Errors::Internal
      def initialize(page_size)
        super("#{page_size} exceeds the maximum limit of #{Platform::Schema::ABSOLUTE_MAX_PER_PAGE}.")
      end
    end
  end
end
