# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ExcessivePagination < Errors::Execution
      TYPE = "EXCESSIVE_PAGINATION"
      def initialize(field, arg_name, requested_per_page, max_per_page)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super(TYPE, "Requesting #{requested_per_page} records on #{phrase} exceeds the `#{arg_name}` limit of #{max_per_page} records.")
      end
    end
  end
end
