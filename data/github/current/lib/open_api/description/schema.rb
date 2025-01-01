# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class Schema
      TYPE_MAP = {
        "array"   => [Array],
        "boolean" => [FalseClass, TrueClass],
        "integer" => [Integer],
        "number"  => [Integer, Float],
        "null"    => [NilClass],
        "object"  => [Hash],
        "string"  => [String],
      }.freeze

      # @param raw [Hash] a hash representing an OpenAPI Schema Object
      def initialize(raw)
        @raw = raw
      end

      def skip_validation?
        @raw.fetch("x-skip-runtime-validation", false)
      end

      def title
        @raw["title"]
      end

      def description
        @raw["description"]
      end

      def type
        @raw["type"]
      end

      def ruby_types
        if type.is_a?(Array)
          type.map { |t| TYPE_MAP[t] }.flatten.compact
        else
          TYPE_MAP.fetch(@raw["type"], nil)
        end
      end

      def properties
        (@raw["properties"] || []).each_with_object({}) do |(prop, schema), obj|
          obj[prop] = self.class.new(schema)
        end
      end

      def raw_additional_properties
        @raw["additionalProperties"]
      end

      def with_additional_properties(value, &block)
        original_value = @raw["additionalProperties"]
        @raw["additionalProperties"] = value
        yield
      ensure
        @raw["additionalProperties"] = original_value
      end

      def additional_properties
        return true if @raw["additionalProperties"].nil?

        return @raw["additionalProperties"] unless @raw["additionalProperties"].respond_to?(:each)
        return @raw["additionalProperties"] if @raw["additionalProperties"].blank?

        self.class.new(@raw["additionalProperties"])
      end

      def required
        @raw["required"] || []
      end

      def enum
        @raw["enum"]
      end

      def case_insensitive_enum?
        !!@raw["x-case-insensitive-enum"]
      end

      def graceful_enum?
        !!@raw["x-graceful-enum"]
      end

      def format
        @raw["format"]
      end

      def default
        @raw["default"]
      end

      # Sub Schemas

      def all_of
        @all_of ||= @raw["allOf"].map { |s| self.class.new(s) } if @raw["allOf"]
      end

      def any_of
        @any_of ||= @raw["anyOf"].map { |s| self.class.new(s) } if @raw["anyOf"]
      end

      def one_of
        @one_of ||= @raw["oneOf"].map { |s| self.class.new(s) } if @raw["oneOf"]
      end

      def not
        @raw["not"]
      end

      def has_sub_schema?
        !sub_schemas.blank?
      end

      def sub_schemas
        [one_of, any_of, all_of].compact.flatten
      end

      def items
        self.class.new(@raw["items"]) if @raw["items"]
      end

      # OpenAPI Specific Fields

      def deprecated
        @raw["deprecated"]
      end

      def nullable
        if OpenApi.version == OpenApi::CURRENT_VERSION
          !!@raw["nullable"]
        elsif OpenApi.version == OpenApi::NEXT_VERSION
          if has_sub_schema?
            sub_schemas.any?(&:nullable)
          else
            return false unless @raw["type"]
            Array(@raw["type"]).include?("null")
          end
        end
      end

      alias_method :nullable?, :nullable

      def discriminator
        raise NotImplementedError
      end

      def read_only
        raise NotImplementedError
      end

      def write_only
        raise NotImplementedError
      end

      def external_docs
        raise NotImplementedError
      end

      def example
        raise NotImplementedError
      end

      # Misc JSON Schema Validations

      def multiple_of
        @raw["multiple_of"]
      end

      def maximum
        @raw["maximum"]
      end

      def minimum
        @raw["minimum"]
      end

      def max_length
        @raw["maxLength"]
      end

      def min_length
        @raw["minLength"]
      end

      def exclusive_maximum
        @raw["exclusiveMaximum"]
      end

      def exclusive_minimum
        @raw["exclusiveMinimum"]
      end

      def pattern
        if @raw["pattern"]
          Regexp.new(@raw["pattern"])
        end
      end

      def max_items
        @raw["maxItems"]
      end

      def min_items
        @raw["minItems"]
      end

      def unique_items
        @raw["uniqueItems"]
      end

      def max_properties
        @raw["maxProperties"]
      end

      def min_properties
        @raw["minProperties"]
      end
    end
  end
end
