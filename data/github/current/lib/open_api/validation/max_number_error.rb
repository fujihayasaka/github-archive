# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MaxNumberError < OpenApi::Validation::SchemaError
      code :number_too_large

      def public_message
        "Must be at most #{object.maximum}."
      end

      def developer_message
        <<~MD
        The request failed because the property's value was too large.

        #{public_message}
        MD
      end
    end
  end
end
