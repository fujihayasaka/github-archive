# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MaxItemsError < OpenApi::Validation::SchemaError
      code :invalid_max_items

      def public_message
        "No more than #{object.max_items} item" +
            (object.max_items == 1 ? " is" : "s are") +
            " allowed; #{data.size} " +
            (data.size == 1 ? "was" : "were") +
            " supplied."
      end

      def developer_message
        <<~MD
        The request failed because the request specified too many items.

        #{public_message}

        Either reduce the number of items supplied or increase the `max_items` specified in the operation.
        MD
      end

    end
  end
end
