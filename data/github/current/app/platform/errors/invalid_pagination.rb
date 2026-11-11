# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class InvalidPagination < Errors::Execution
      TYPE = "INVALID_PAGINATION"
      def initialize(field, arg_name)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super(TYPE, "`#{arg_name}` on #{phrase} cannot be less than zero.")
      end
    end
  end
end
