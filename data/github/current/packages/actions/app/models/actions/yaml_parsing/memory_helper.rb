# typed: true
# frozen_string_literal: true

require "yaml"
require_relative "./user_error"

module Actions
  module YamlParsing
    # Helper class for memory-safe operations during YAML parsing
    class MemoryHelper
      # Constants for memory tracking
      MIN_OBJECT_SIZE = 24
      STRING_BASE_OVERHEAD = 26

      # Expose current_bytes for testing
      attr_reader :current_bytes

      # Initialize a new memory tracker with a maximum byte limit
      # @param max_bytes [Integer] Maximum memory usage allowed in bytes
      def initialize(max_bytes)
        # Validate max_bytes
        if max_bytes.nil? || max_bytes <= 0
          raise ArgumentError, "max_bytes must be a positive integer"
        end

        @max_bytes = max_bytes
        @current_bytes = 0
      end

      # Track memory usage for a YAML node
      # This measurement doesn't have to be perfect. Approximation is sufficient.
      # @param node [Psych::Nodes::Node] The YAML node to track
      # @raise [YamlParsingError] If memory limit is exceeded
      def add_bytes(node)
        if node.is_a?(Psych::Nodes::Scalar)
          value = node.to_ruby
          if value.is_a?(String)
            # For strings, account for the node itself plus string overhead and content
            # Inspired by https://codeblog.jonskeet.uk/2011/04/05/of-memory-and-strings/
            @current_bytes += MIN_OBJECT_SIZE + STRING_BASE_OVERHEAD + value.length + value.length
          else
            # For non-string scalars, count object overhead
            @current_bytes += MIN_OBJECT_SIZE
          end
        elsif node.is_a?(Psych::Nodes::Mapping) || node.is_a?(Psych::Nodes::Sequence)
          # For mapping or sequence, count object overhead
          @current_bytes += MIN_OBJECT_SIZE
        else
          raise "Unexpected node type #{node.class}"
        end

        # Check if we've exceeded the memory limit
        if @current_bytes > @max_bytes
          raise UserError, "Maximum memory usage exceeded during YAML parsing (#{@max_bytes} bytes)"
        end
      end
    end
  end
end
