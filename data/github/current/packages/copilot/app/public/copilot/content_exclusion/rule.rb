# typed: strict
# frozen_string_literal: true

require "psych/nodes"

module Copilot
  module ContentExclusion
    class Rule < T::Struct
      include GitHub::Memoizer
      include DocumentErrorHelpers

      const :scope, T.nilable(String), default: nil # nil is for repo-level rules
      const :patterns, T::Array[String], default: []

      const :if_none_match, T::Array[String], default: []
      const :if_any_match, T::Array[String], default: []

      const :allow_text_based_rules, T::Boolean, default: false

      sig { returns(T::Boolean) }
      memoize def is_all_scoped?
        @scope == "*"
      end

      sig { params(node: T.any(Psych::Nodes::Scalar, Psych::Nodes::Mapping)).void }
      def add_policies_from_node(node)
        if node.is_a?(Psych::Nodes::Scalar)
          validate_path_pattern!({ value: node.value, location: [node.start_line, node.start_column] })
          @patterns << node.value unless node.value.blank?
          return
        end

        return report_node_error("Expecting a path pattern", node) unless @allow_text_based_rules

        # If @allow_text_based_rules is true, then we are in the "content aware feature" realm

        node.children.each_slice(2) do |key, value|
          return report_node_error("Expecting a property of either `ifNoneMatch` or `ifAnyMatch`", key) unless key.is_a?(Psych::Nodes::Scalar) && %w[ifNoneMatch ifAnyMatch].include?(key.value)
          return report_node_error("Expecting an array of regular expressions", value) unless value.is_a?(Psych::Nodes::Sequence)

          value.children.each do |item|
            return report_node_error("Expecting a scalar value", value) unless item.is_a?(Psych::Nodes::Scalar)

            begin
              Regexp.new(item.value)
            rescue RegexpError => e
              return report_node_error("Invalid regular expression: #{e.message}", item)
            end

            case key.value
            when "ifNoneMatch"
              @if_none_match << item.value
            when "ifAnyMatch"
              @if_any_match << item.value
            end
          end
        end
      end

      sig { params(other: Rule).returns(T::Boolean) }
      def ==(other)
        other.scope == @scope &&
          other.patterns == @patterns &&
          other.if_none_match == @if_none_match &&
          other.if_any_match == @if_any_match &&
          other.allow_text_based_rules == @allow_text_based_rules
      end
    end
  end
end
