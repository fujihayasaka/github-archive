# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MaxStringLengthError < OpenApi::Validation::SchemaError
      code :invalid_max_string_length_error

      def public_message
        %{Only #{object.max_length} character} +
         (object.max_length == 1 ? " is" : "s are") +
         %{ allowed; #{data.length} } +
         (data.length == 1 ? "was" : "were") +
         %{ supplied.}
      end

      def developer_message
        <<~MD
        The request failed because the specified string is too long.

        #{public_message}

        Either reduce the number of characters supplied or increase the `max_length` specified in the operation.
        MD
      end

    end
  end
end
