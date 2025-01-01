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
      # unwrapping and normalizing strings and escaped sequences
      rule(string: simple(:content)) do
        IssuesTransformer.unescape_string_content(content)
      end

      # Quoted text term is used to support exact text matches
      rule(quoted_text_term: subtree(:content)) do
        string_content = if content.is_a?(Hash) && content.has_key?(:string)
          IssuesTransformer.unescape_string_content(content[:string])
        else
          content
        end

        # > double quotes (") are stripped by both texty tokenizers and won't be considered in exact matches.
        # > By replacing them with an empty space, they keep the same token "semantic" value
        # > and make it easier to identify text terms with phrases in them by checking the existence of
        # > double quotes
        string_content = string_content.gsub('"', " ")

        # making the contet an ElasticSearch phrase
        { text_term: "\"#{string_content}\"" }
      end

      # unwrapping filter value
      rule(filter_value: subtree(:content)) { content }

      # unwrap ANDs
      rule(and: { left: subtree(:left), right: subtree(:right), explicit_operator: subtree(:explicit_operator) }) do
        IssuesTransformer.unwrap_and(left, right)
      end

      rule(and: { left: subtree(:left), right: subtree(:right) }) do
        IssuesTransformer.unwrap_and(left, right)
      end

      # unwrap ORs
      rule(or: { left: subtree(:left), right: subtree(:right), explicit_operator: subtree(:explicit_operator) }) do
        unwrapped_left = (left.is_a?(Hash) && left.key?(:or)) ? left[:or] : left
        unwrapped_right = (right.is_a?(Hash) && right.key?(:or)) ? right[:or] : right

        { or: [unwrapped_left, unwrapped_right].flatten }
      end

      def self.unwrap_and(left, right)
        unwrapped_left = (left.is_a?(Hash) && left.key?(:and)) ? left[:and] : left
        unwrapped_right = (right.is_a?(Hash) && right.key?(:and)) ? right[:and] : right

        if IssuesTransformer.text_term_subtree?(unwrapped_left)
          if IssuesTransformer.text_term_subtree?(unwrapped_right)
            return { text_term: "#{unwrapped_left[:text_term]} #{unwrapped_right[:text_term]}" }
          elsif unwrapped_right.is_a?(Array) && IssuesTransformer.text_term_subtree?(unwrapped_right.first)
            unwrapped_right.first[:text_term] = "#{unwrapped_left[:text_term]} #{unwrapped_right.first[:text_term]}"
            return { and: unwrapped_right }
          end
        end

        { and: [unwrapped_left, unwrapped_right].flatten }
      end

      def self.text_term_subtree?(subtree)
        subtree && subtree.is_a?(Hash) && subtree.has_key?(:text_term)
      end

      # normalize escaped sequences
      def self.unescape_string_content(string_content)
        string_content.to_str
          .gsub("\\'", "'")
          .gsub('\\"', '"')
      end
    end
  end
end
