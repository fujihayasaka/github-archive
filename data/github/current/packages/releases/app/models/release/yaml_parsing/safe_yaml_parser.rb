# typed: strict
# frozen_string_literal: true

require "yaml"

module Release::YamlParsing
  class SafeYamlParser
    DEFAULT_MAX_DEPTH = 50

    class UserError < StandardError; end

    class DepthChecker < Psych::Handler
      sig { params(max_depth: Integer).void }
      def initialize(max_depth)
        @max_depth = T.let(max_depth, Integer)
        @depth = T.let(0, Integer)
      end

      sig { params(_anchor: T.untyped, _tag: T.untyped, _implicit: T.untyped, _style: T.untyped).void }
      def start_mapping(_anchor, _tag, _implicit, _style)
        increment_depth
      end

      sig { void }
      def end_mapping
        decrement_depth
      end

      sig { params(_anchor: T.untyped, _tag: T.untyped, _implicit: T.untyped, _style: T.untyped).void }
      def start_sequence(_anchor, _tag, _implicit, _style)
        increment_depth
      end

      sig { void }
      def end_sequence
        decrement_depth
      end

      private

      sig { void }
      def increment_depth
        @depth += 1
        raise UserError, "Max YAML depth exceeded" if @depth > @max_depth
      end

      sig { void }
      def decrement_depth
        @depth -= 1 if @depth.positive?
      end
    end

    sig { params(content: String, max_depth: Integer).returns(T.untyped) }
    def self.safe_load(content, max_depth: DEFAULT_MAX_DEPTH)
      raise ArgumentError, "max_depth must be a positive integer" if max_depth <= 0

      Psych::Parser.new(DepthChecker.new(max_depth)).parse(content)
      YAML.safe_load(content)
    rescue Psych::Exception => e
      raise UserError, e.message
    end
  end
end
