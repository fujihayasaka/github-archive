# typed: false
# frozen_string_literal: true

module OpenApi
  module Validation
    class MissingRequiredKeysError < OpenApi::Validation::SchemaError
      code :invalid_required

      def initialize(*args, keys:, **kwargs)
        super(*args, **kwargs)
        @keys = keys
      end

      def public_message
        "object is missing required key" +
        (@keys.size == 1 ? "" : "s") +
        ": #{@keys.join(", ")}."
      end

      def developer_message
        <<~MD
        The following required parameters are missing:

        #{@keys.map { |k| "- #{k}" }.join("\n")}

        Either add those keys, or remove them from the `required:` list.

        MD
      end
    end
  end
end
