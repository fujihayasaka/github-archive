# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Root
      attr_reader :raw

      def initialize(description)
        @raw = description
      end

      def paths
        @raw["paths"]
      end

      def version
        @raw["info"]["version"]
      end

      # Public: A flat hash map of operation_id -> operation.
      #
      # Returns a Hash
      def operations
        @operations ||= paths.reduce({}) do |acc, (path, operations)|
          operations.each do |http_method, operation_ref|
            operation_key = "#{http_method} #{path}"
            acc["#{operation_key}"] = operation_ref
          end

          acc
        end
      end

      def webhooks
        @raw[OpenApi.webhook_key]
      end
    end
  end
end
