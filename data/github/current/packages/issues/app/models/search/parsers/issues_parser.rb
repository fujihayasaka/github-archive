# typed: false
# frozen_string_literal: true

require "parslet"

##
# This parser supports the new issues advanced search grammar, which is too complex
# to be handled solely by Regular Expressions.
# e.g: `((is:issue AND label:bug) OR author:monalisa)`
#
# To parse an input string, create an instance of this class, and call its parse method
#
# parser = ::Search::Parsers::IssuesParser.new
# ast = parser.parse(input_string)
#
# To better understand the mapping between input string and generated tree,
# refer to the test files.
#

module Search
  module Parsers
    class IssuesParser < Parslet::Parser
      rule(:space)            { match[" \t"].repeat(1) }
      rule(:space?)           { space.maybe }
      rule(:white_space)      { match["\\s"].repeat(1) } # matches: space, \t, \r, \n, \v
      rule(:white_space?)     { white_space.maybe }
      rule(:double_quotation) { str('"') }
      rule(:single_quotation) { str("'") }
      rule(:comma)            { str(",") }
      rule(:lparen)           { str("(") }
      rule(:rparen)           { str(")") }
      rule(:colon)            { str(":") }
      rule(:at)               { str("@") }
      rule(:slash)            { str("/") }
      rule(:negative_symbol)  { str("-") }
      rule(:backslash)        { str("\\") }
      rule(:line_break)       { str("\n") | str("\r") }

      # double_quotation is added as a reserverd characters to allow users to catch query typos more easily
      rule(:reserved_characters)  { white_space | lparen | rparen | double_quotation }

      rule(:no_modifier)        { str("no") }
      rule(:and_operator)       { str("AND") }
      rule(:or_operator)        { str("OR") }

      rule(:reserved_keywords)  { and_operator | or_operator }

      # Rule to disambiguate AND and OR operators from a simple non-quoted text term
      rule(:text_term) do
        # > match unquoted strings that don't start with AND or OR
        (reserved_keywords.absent? >> ((reserved_characters.absent? >> any).repeat(1)).as(:text_term)) |
        # > match unquoted strings that start with AND or OR and have at least 4 length
        (reserved_keywords >> (reserved_characters.absent? >> any).repeat(1)).as(:text_term)
      end

      # Double quoted strings follow the format:
      #   "{any_allowed_character}+"
      #   and support 2 escape sequences:
      #     - \\: to escape backslash
      #     - \": to escape double quotation mark
      rule(:double_quoted_string_not_allowed_characters) { double_quotation | line_break }
      rule(:double_quoted_escape_sequences) { str("\\\\") | str("\\\"") }
      rule(:double_quoted_string) do
        double_quotation >> (
          double_quoted_escape_sequences | (double_quoted_string_not_allowed_characters.absent? >> any)
        ).repeat(1).as(:string) >>
        double_quotation.maybe
      end

      # Single quoted strings follow the format:
      #   '{any_allowed_character}+'
      #   and support 2 escape sequences:
      #     - \\: to escape the backslash
      #     - \': to escape the single quotatiob mark
      rule(:single_quoted_string_not_allowed_characters) { single_quotation | line_break }
      rule(:single_quoted_escape_sequences) { str("\\\\") | str("\\'") }
      rule(:single_quoted_string) do
        single_quotation >> (
          single_quoted_escape_sequences | (single_quoted_string_not_allowed_characters.absent? >> any)
        ).repeat(1).as(:string) >>
        single_quotation.maybe
      end

      rule(:quoted_strings) { double_quoted_string | single_quoted_string }

      # Mentions can reference users or repositories:
      #   @{username}
      #   -@{username}
      #   @{username}/{repository}
      #   -@{username}/{repository}
      rule(:mention_name_qualifier) { match('[\w\-.]').repeat(1) }
      rule(:mention_term) do
        negative_symbol.maybe.as(:negative) >> at >>
        mention_name_qualifier.as(:user_value) >>
        (slash >> mention_name_qualifier.as(:repository_value)).maybe
      end

      # Filters are composed of:
      #   {filter_qualifier}:{filter_value}
      #   -{filter_qualifier}:filter_value
      rule(:filter_term) do
        negative_symbol.maybe.as(:negative) >> filter_qualifier >> colon >> filter_value
      end

      # Rule to match a filter qualifier (the part of a filter that comes before the colon ":"):
      #   {filter_qualifier}:{filter_value}
      #   └────────────────┘
      # > the name of a qualifier can be more strict since it isn't defined by the used and has to match
      # a supported filter
      rule(:filter_qualifier) { match('[a-zA-Z_0-9\-\+]').repeat(1).as(:attribute) }

      # Rule to be applied to the value part of a filter:
      #   {filter_qualifier}:{filter_value}
      #                      └────────────┘
      # > the value is more permissive than the name since it can have a label name
      # and label names allow for almost all characters, except commas (,)
      rule(:filter_value) { filter_enumerated_values.as(:value) }

      rule(:filter_value_not_allowed_characters) { comma | white_space | double_quotation | single_quotation | lparen | rparen }
      rule(:filter_string_value) do
        (filter_value_not_allowed_characters.absent? >> any).repeat(1)
      end

      rule(:filter_enumerated_values) { (filter_enumerated_value >> comma.maybe).repeat(1) }
      rule(:filter_enumerated_value) { (quoted_strings | filter_string_value).as(:filter_value) }

      rule(:filter_no_modifier) { no_modifier.as(:missing) >> colon >> filter_qualifier }

      # :filter_no_modifier has to come before filter, since the "no:" prefix could also be captuted by
      # the :filter_term rule
      rule(:filter) { filter_no_modifier | filter_term }

      # this represents leaf expressions of the search query
      rule(:term) do
        mention_term.as(:mention_term) |
        quoted_strings.as(:quoted_text_term) |
        filter.as(:filter_term) |
        text_term
      end

      # parses an expression with parenthesis recursively, or matches a leaf :term
      rule(:term_expression) do
        (lparen >> white_space? >> or_expression >> white_space? >> rparen) |
        term
      end

      rule(:implicit_and_expression) do
        (term_expression.as(:left) >> white_space >> and_expression.as(:right)).as(:and)
      end

      rule(:and_expression) do
        # explicit and -> LEFT and RIGHT
        (term_expression.as(:left) >>
          white_space >> and_operator.as(:explicit_operator) >> white_space >>
          and_expression.as(:right)).as(:and) |
        # implicit and -> LEFT RIGHT
        implicit_and_expression |
        term_expression
      end

      rule(:or_expression) do
        (
          and_expression.as(:left) >>
          white_space >> or_operator.as(:explicit_operator) >> white_space >>
          or_expression.as(:right)
        ).as(:or) |
        and_expression
      end

      rule(:root_operation) do
        or_expression.as(:root)
      end

      root(:root_operation)

      # trim the query string before parsing it
      def parse(str)
        str = str.gsub(/("[^"]*")|[ \t\r\n]+/) do
          $1 ? $1 : " " # If inside double quotes ($1), preserve; otherwise replace with a single space
        end.strip
        return { root: nil } if str.empty?
        super(str)
      end
    end
  end
end
