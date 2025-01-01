# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MinStringLengthError < OpenApi::Validation::SchemaError
      code :invalid_min_string_length_error

      def public_message
        %{At least #{object.min_length} character} +
         (object.min_length == 1 ? " is" : "s are") +
         %{ allowed; #{data.length} } +
         (data.length == 1 ? "was" : "were") +
         %{ supplied.}
      end

      def developer_message
        <<~MD
        #{public_message}

        Either provide a longer string or increase the `minLength` specified in the operation.
        MD
      end

    end
  end
end
