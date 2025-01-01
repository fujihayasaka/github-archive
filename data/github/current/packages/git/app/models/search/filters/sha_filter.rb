# typed: true
# frozen_string_literal: true

module Search
  module Filters
    class ShaFilter < ::Search::Filter
      def initialize(opts = {})
        super(opts)
        map_bool_collection do |value|
          if value =~ /\A[0-9a-f]{7,40}\z/
            value.downcase
          else
            @valid = false
            nil
          end
        end
      end

      def invalid_reason
        "The given commit SHA is not in a recognized format"
      end

      # Internal: Generate a filter hash from the given values.
      #
      # values - The prefix filter values as an Array of Strings.
      #
      # Returns a filter Hash or nil.
      def build(values)
        if values && values.length == 1
          { prefix: { field => values.first } }
        end
      end
    end  # PrefixFilter
  end  # Filters
end  # Search
