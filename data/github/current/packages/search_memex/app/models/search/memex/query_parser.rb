# typed: true
# frozen_string_literal: true

module Search
  module Memex::QueryParser
    include Kernel

    class QuerySyntaxError < StandardError; end

    extend self

    QUALIFIER_LEXEMES = {
      START: /(?<=\s|\A|\s-|\A-)/, # Start of string, whitespace with optional negative token
      UNQUOTED: /(?=[^-])(?:[^:\s\\\"\']+|[^:\s\"][^:\s\"]+)/, # Single character allowed if not \,",',-
      DOUBLE_QUOTED: /(?:\"[^:\s\"]+\")/, # With surrounding double quotes
      END: /(?=:.*)/, # Colon followed by anything
    }

    # Describes all available lexemes for parsing
    # QUALIFIERS: Field name includes any non-whitespace characters except : to allow for emojis
    LEXEMES = {
      QUOTES: /"/,
      COMMA: /,/,
      SPLIT: /:/,
      ALL: /.+/,
      QUALIFIERS: /#{QUALIFIER_LEXEMES[:START]}#{Regexp.union(QUALIFIER_LEXEMES[:UNQUOTED], QUALIFIER_LEXEMES[:DOUBLE_QUOTED])}#{QUALIFIER_LEXEMES[:END]}/,
      WHITESPACE: /\s+/,
      # Matches standalone single-quoted strings (even when they contain colons).
      #
      # Examples:
      #
      #   hello'world:value'bar 'start':'date' matches 'start' and 'date'
      #   'hello':'world' matches both 'hello' and 'world'
      #   'my':'fi:eld' matches both 'my' and 'fi:eld'
      #   hello'world:12/21/2025 foo'bar:value matches nothing
      #   double-'single'-quotes:'value' matches 'value'
      #   'foo'-bar:value matches nothing
      BETWEEN_QUOTES: /(?<!\w|-)(?<!")'[^']*'(?!")(?!:|[-\w])/,
      DOUBLE_QUOTED: /"[^"]+"/,
      WRAPPING_DOUBLE_QUOTED: /\A\\?\"([^"]+)\\?\"\Z/,
      # Matches on a quoted string followed by an optional range operator with another quoted string.
      #
      # Examples:
      #
      #   "Sprint 1"
      #   "Sprint 1".."Sprint 6"
      QUOTED_RANGE: /"(?:(?<=\\)"|[^"])*"(?:\.\."(?:(?<=\\)"|[^"])*")/
    }

    # Parses a string query into a hash of keywords and values
    #
    # Ignores non-tokens (e.g. :keyword, keyword:), whitespace and single words
    #
    # @return [Array<Hash>]
    # [{
    #    keyword: Symbol,
    #    values: Array<String>,
    #    exclude: Boolean
    # }]
    sig do
      params(
        query: T.nilable(String),
        normalizer: T.proc.params(query: String).returns(String),
        context: T.nilable(Search::Memex::Context),
      )
      .returns(T::Array[T::Hash[T.untyped, T.untyped]])
    end
    def parse(query, normalizer: -> (query) { query.strip }, context: nil)
      tokens = tokenize(query, normalizer:, context:)
      begin
        lex_tokens(tokens)
      rescue QuerySyntaxError
        []
      end
    end

    def equal?(*queries)
      queries.map { |q| group_query_tokens_by_values(parse(q)) }.uniq.count <= 1
    end

    # Split a string into a list of tokens
    # Correct token formats is <optional-minus><keyword>:<value> and <optional-minus><keyword>:<value1>,<value2>,...
    #
    # Keywords and Values can contain any character, except :"',
    # Values can be:
    #   - single: value | dash-value
    #   - composite: "composite value" | 'composite value'
    #   - operand value: <value | >value | <=value | >=value
    #
    # Tokens are separated by a whitespace
    sig do
      params(
        query: T.nilable(String),
        normalizer: T.proc.params(query: String).returns(String),
        context: T.nilable(Search::Memex::Context),
      )
      .returns(T::Array[String])
    end
    private def tokenize(query, normalizer: -> (query) { query.downcase.strip }, context: nil)
      return [] if query.blank?

      # Replace values between single quotes with double quotes
      normalizer_regex = LEXEMES[:BETWEEN_QUOTES]
      normalized_query = normalizer.call(query).gsub(normalizer_regex) { |match| match.gsub("'", "\"") }

      qualifiers_pattern = LEXEMES[:QUALIFIERS]
      qualifiers = normalized_query.scan(qualifiers_pattern).flatten.map(&:to_sym)
      Search::ParsedQuery.parse(normalized_query, terms: qualifiers, escape_terms: true, normalize_quotes: false, viewer: context&.viewer).map do |parsed|
        if parsed.is_a?(String)
          values = parsed.split(LEXEMES[:WHITESPACE]).map(&:strip)

          # Memex doesn't currently support negative free text queries.
          # i.e., `-foo` is parsed as `IS '-foo'` rather than `NOT 'foo'`.
          values.map { |v| "_:#{v}" }
        else
          "#{(parsed.third ? "-" : "")}#{parsed.first}:#{parsed.second.strip}"
        end
      end.flatten.compact
    end

    # Parse tokens into a list of formatted hashes
    private def lex_tokens(tokens)
      tokens.map { |token| parse_token(token) }
    end

    # Parses a single token pair into a hash
    #
    # Note:
    #   - negative tokens `-key:value` are parsed into positive symbols `key`
    #   - wrapping quotes are dropped from keys
    #   - quotes are dropped from composite values
    #
    # @return { keyword: Symbol, values: Array<String>, exclude: Boolean }
    private def parse_token(token)
      negative = token.start_with?("-")
      token.delete_prefix!("-") if negative
      qs = StringScanner.new token
      key = qs.scan_until(LEXEMES[:SPLIT])&.gsub(LEXEMES[:SPLIT], "")
      key = key&.gsub(LEXEMES[:WRAPPING_DOUBLE_QUOTED], '\1')

      values = []
      # Scan the string until we find a comma
      while match = qs.check_until(LEXEMES[:COMMA])
        # The match includes a double-quote, so we don't wish to break on this comma. Scan until the next double-quote
        # instead, and strip those quotes.
        if match.include?("\"")
          raw_value = qs.scan_until(LEXEMES[:DOUBLE_QUOTED])
          raise QuerySyntaxError unless raw_value
          value = raw_value.gsub(LEXEMES[:QUOTES], "")
        else
          # The match does not include a double-quote. Stop at this comma.
          value = qs.scan_until(LEXEMES[:COMMA]).gsub(LEXEMES[:COMMA], "").gsub(LEXEMES[:QUOTES], "")
        end

        if !value.empty?
          values << value
        end
      end

      while qs.check_until(LEXEMES[:QUOTED_RANGE])
        value = qs.scan_until(LEXEMES[:QUOTED_RANGE])
        values << value
      end

      # parse last part of value
      while qs.check_until(LEXEMES[:ALL])
        value = qs.scan_until(LEXEMES[:ALL]).gsub(LEXEMES[:QUOTES], "")
        values << value
      end

      { keyword: key.to_sym, values: values, exclude: negative }
    end

    # Group and reduce tokens by :keyword and :exclude keys and compare values
    # e.g. Given [
    #   {:keyword=>:is, :values=>["issue", "pr"], :exclude=>false},
    #   {:keyword=>:is, :values=>["open"], :exclude=>false},
    #   {:keyword=>:label, :values=>["blah"], :exclude=>false},
    #   {:keyword=>:milestone, :values=>["test"], :exclude=>true}
    # ]
    # returns {:is=>{false=>["issue", "open", "pr"]}, :label=>{false=>["blah"]}, :milestone=>{true=>["test"]}}
    private def group_query_tokens_by_values(token)
      token.group_by { |t| t[:keyword] }.transform_values do |keyword_values|
        keyword_values.group_by { |k| k[:exclude] }.transform_values do |exclude_values|
          exclude_values.map { |e| e.select { |e, _| e == :values } }
            .map(&:values)
            .flatten
            .sort
        end
      end
    end
  end
end
