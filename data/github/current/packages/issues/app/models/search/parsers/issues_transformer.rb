# typed: false
# frozen_string_literal: true

require "parslet"

##
# The transform is used to simplify the parsed tree
#
# Its main goal is to reduce nested expressions and unwrap captues.
# A parsed tree similar to:
#   { and: {
#      left: { and: { left: A, right: { and: { left: B, right: C } } } },
#       right: { and: { left: D, right: E } } }
#   }
# will be transformed to:
#   { and: [A, B, C, D, E] }
# That's equivalent to the first tree due to the associative property of ANDs and ORs.
#
# For complete examples, check the test file for the Transformer
#

module Search
  module Parsers
    class IssuesTransformer < Parslet::Transform
      # unwrapping and unescaping strings
      rule(string: simple(:content)) { content.to_str.gsub('\\"', '"').gsub("\\'", "'") }

      # unwrapping filter value
      rule(filter_value: subtree(:content)) { content }

      # unwrap ANDs
      rule(and: { left: subtree(:left), right: subtree(:right) }) do
        unwrapped_left = (left.is_a?(Hash) && left.key?(:and)) ? left[:and] : left
        unwrapped_right = (right.is_a?(Hash) && right.key?(:and)) ? right[:and] : right

        { and: [unwrapped_left, unwrapped_right].flatten }
      end

      # unwrap ORs
      rule(or: { left: subtree(:left), right: subtree(:right) }) do
        unwrapped_left = (left.is_a?(Hash) && left.key?(:or)) ? left[:or] : left
        unwrapped_right = (right.is_a?(Hash) && right.key?(:or)) ? right[:or] : right

        { or: [unwrapped_left, unwrapped_right].flatten }
      end
    end
  end
end
