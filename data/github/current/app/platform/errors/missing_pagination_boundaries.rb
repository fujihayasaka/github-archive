# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class MissingPaginationBoundaries < Errors::Execution
      TYPE = "MISSING_PAGINATION_BOUNDARIES"
      def initialize(field)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super(TYPE, "You must provide a `first` or `last` value to properly paginate #{phrase}.")
      end
    end
  end
end
