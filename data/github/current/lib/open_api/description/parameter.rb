# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Parameter
      attr_reader :schema, :index

      def initialize(parameter, index)
        @raw    = parameter
        @schema = Schema.new(@raw["schema"])
        @index = index
      end

      def required?
        @raw["required"]
      end

      def in
        @raw["in"]
      end

      def multi_segment?
        !!@raw["x-multi-segment"]
      end

      def name
        @raw["name"]
      end

      def json_pointer
        ["parameters", @index, "schema"]
      end
    end
  end
end
