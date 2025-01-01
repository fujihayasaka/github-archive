# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MinNumberError < OpenApi::Validation::SchemaError
      code :number_too_small

      def public_message
        "Must be at least #{object.minimum}."
      end

      def developer_message
        <<~MD
        The request failed because the property's value was too small.

        #{public_message}
        MD
      end

    end
  end
end
