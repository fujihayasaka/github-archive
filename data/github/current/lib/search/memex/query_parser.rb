# typed: true
# frozen_string_literal: true

module Search
  module Memex::QueryParser
    include Kernel

    class QuerySyntaxError < StandardError; end

    extend self

    # Describes all available lexemes for parsing
    # QUALIFIERS: Field name includes any non-whitespace characters to allow for emojis
    Lexemes = {
      QUOTES: /"/,
      COMMA: /,/,
      SPLIT: /:/,
      ALL: /.+/,
      QUALIFIERS: /[^\s"]+(?=\:\S)/,
      WHITESPACE: /\s+/,
      BETWEEN_QUOTES: /'[^,]+(?=',*)'/,
      DOUBLE_QUOTED: /"[^"]+"/,
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
        normalizer: T.proc.params(query: String).returns(String)
      )
      .returns(T::Array[T::Hash[T.untyped, T.untyped]])
    end
    def parse(query, normalizer: -> (query) { query.downcase.strip })
      tokens = tokenize(query, normalizer: normalizer)
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
    #   - composite: "comoposite value" | 'comoposite value'
    #   - operand value: <value | >value | <=value | >=value
    #
    # Tokens are separated by a whitespace
    sig do
      params(
        query: T.nilable(String),
        normalizer: T.proc.params(query: String).returns(String)
      )
      .returns(T::Array[String])
    end
    private def tokenize(query, normalizer: -> (query) { query.downcase.strip })
      return [] if query.blank?

      # Replace values between single quotes with double quotes
      normalized_query = normalizer.call(query)
        .gsub(Lexemes[:BETWEEN_QUOTES]) { |match| match.gsub("'", "\"") }

      escaped_query = escape_query(normalized_query)

      qualifiers = escaped_query.scan(Lexemes[:QUALIFIERS]).flatten.map(&:to_sym)
      Search::ParsedQuery.parse(escaped_query, terms: qualifiers, escape_terms: true, normalize_quotes: false).map do |parsed|
        if parsed.is_a?(String)
          values = parsed.split(Lexemes[:WHITESPACE]).map(&:strip)
          values.map { |v| v.start_with?("-") ? "-_:#{v[1..-1]}" : "_:#{v}" }
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
    #   - quotes are droped from composite values
    #
    # @return { keyword: Symbol, values: Array<String>, exclude: Boolean }
    private def parse_token(token)
      negative = token.start_with?("-")
      token.delete_prefix!("-") if negative
      qs = StringScanner.new token
      key = qs.scan_until(Lexemes[:SPLIT])&.gsub(Lexemes[:SPLIT], "")

      values = []
      # Scan the string until we find a comma
      while match = qs.check_until(Lexemes[:COMMA])
        # The match includes a double-quote, so we don't wish to break on this comma. Scan until the next double-quote
        # instead, and strip those quotes.
        if match.include?("\"")
          raw_value = qs.scan_until(Lexemes[:DOUBLE_QUOTED])
          raise QuerySyntaxError unless raw_value
          value = raw_value.gsub(Lexemes[:QUOTES], "")
        else
          # The match does not include a double-quote. Stop at this comma.
          value = qs.scan_until(Lexemes[:COMMA]).gsub(Lexemes[:COMMA], "").gsub(Lexemes[:QUOTES], "")
        end

        if !value.empty?
          values << value
        end
      end

      # parse last part of value
      while qs.check_until(Lexemes[:ALL])
        value = qs.scan_until(Lexemes[:ALL]).gsub(Lexemes[:QUOTES], "")
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

    # Add escaped quotes around terms that fit the following edge cases:
    #
    #   1. Starts with "-" but is not a key:value pair e.g. "-foo"
    #   2. Starts with ":" e.g. ":bar:baz"
    #
    # This method retains repeated whitespace in between tokens e.g. "foo    bar".
    #
    # Returns the transformed query.
    sig { params(query: String).returns(String) }
    private def escape_query(query)
      # Before escaping the query, we do a simple tokenization to determine where we need to add quotes, which is
      # somewhat semantically accurate and takes care of context-dependent whitespace and colons.
      in_quotes = T.let(false, T::Boolean)
      scanner = StringScanner.new(query)
      current_token = ""
      tokens = []

      until scanner.eos?
        # NOTE: This scanner only looks for quotes, whitespace, or other characters. It is intended to be a lexically
        # accurate "split-by-whitespace" function, not a full tokenizer.
        if scanner.scan(Lexemes[:QUOTES])
          in_quotes = !in_quotes
          current_token += scanner.matched
        elsif scanner.scan(Lexemes[:WHITESPACE])
          # Whitespace is context-dependent: when we're inside of quotes, it is just part of the literal value.
          # Outside of quotes, it is a delimiter between key:value pairs, and denotes the end/start of a token.
          if in_quotes
            current_token += scanner.matched
          else
            tokens << current_token
            current_token = ""
          end
        # If nothing else matches, just read the string character-by-character until we find something we recognize,
        # or we hit the end of the string.
        elsif scanner.getch
          current_token += scanner.matched
        end
      end

      tokens << current_token

      escaped_query = ""
      tokens.each do |token|
        if token[0] == ":" || (token[0] == "-" && !token.include?(":"))
          escaped_query += "\"#{token}\" "
        else
          escaped_query += "#{token} "
        end
      end
      escaped_query.strip
    end
  end
end
