# typed: true
# frozen_string_literal: true

module OpenApi
  module Validation
    class MinItemsError < OpenApi::Validation::SchemaError
      code :invalid_min_items

      def public_message
        "#{object.min_items} item" +
          (object.min_items == 1 ? "" : "s") +
          " required; only #{data.size} " +
          (data.size == 1 ? "was" : "were") +
          " supplied."
      end

      def developer_message
        <<~MD
        The request failed because the request specified too few items.

        #{public_message}

        Either increase the number of items supplied or decrease the `min_items` specified in the operation.
        MD
      end

    end
  end
end
