# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class InvalidNumericPageOrigin < Errors::Execution
      TYPE = "INVALID_NUMERIC_PAGE_ORIGIN"
      def initialize(field, arg_name, origin)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super(TYPE, "`#{arg_name}` on #{phrase} cannot be used in the `#{origin}` origin.")
      end
    end
  end
end
