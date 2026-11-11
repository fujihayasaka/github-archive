# typed: true
# frozen_string_literal: true

module Search
  module Memex::QueryParser
    include Kernel

    class QuerySyntaxError < StandardError; end

    extend self

    SUB_ISSUES_PREFIX = "sub-issues."

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
    # Standalone OR/AND keywords in the query that should be treated as logical operators.
    OR_KEYWORD = "or"
    AND_KEYWORD = "and"
    MAX_PAREN_DEPTH = 5

    # Detects qualifier-like key:value patterns in group content for demotion checks.
    # Requires the key to start with a letter, underscore, or non-ASCII character
    # (excludes timestamps like "12:00") and rejects URL schemes (key://).
    GROUP_QUALIFIER_PATTERN = /(?:\A|(?<=[\s()]))-?(?:[a-zA-Z_\u{80}-\u{10ffff}][^:\s]*):(?!\/\/)/

    sig do
      params(
        query: T.nilable(String),
        normalizer: T.proc.params(query: String).returns(String),
        context: T.nilable(Search::Memex::Context),
        enable_groups: T::Boolean,
      )
      .returns(T::Array[T::Hash[T.untyped, T.untyped]])
    end
    def parse(query, normalizer: -> (query) { query.strip }, context: nil, enable_groups: false)
      return [] if query.blank?

      # If grouping/OR/AND support is enabled and the query contains parentheses, use group-aware parsing.
      if enable_groups && (query.include?("(") || query.include?(")"))
        segments = extract_top_level_segments(query)
        # Demote groups that contain only free text (no qualifiers) so that
        # literal parentheses like "(WIP)" are not misinterpreted as grouping syntax.
        # Empty groups like "()" are dropped entirely.
        segments = segments.filter_map do |segment|
          if segment[:type] == :group && !segment[:content].match?(GROUP_QUALIFIER_PATTERN)
            segment[:content].blank? ? nil : { type: :flat, content: "(#{segment[:content]})" }
          else
            segment
          end
        end
        if segments.any? { |s| s[:type] == :group }
          return parse_with_groups(segments, normalizer:, context:)
        end

        # All groups were demoted or dropped — reconstruct query from remaining
        # flat segments and fall back to flat parsing without logical operator
        # handling to avoid corrupted qualifier keys.
        query = segments.map { |s| s[:content] }.join
        enable_groups = false
      end

      return [] if query.blank?
      tokens = tokenize(query, normalizer:, context:)
      begin
        raw_results = lex_tokens(tokens)
        enable_groups ? mark_logical_operators(raw_results) : raw_results
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

      result = { keyword: key.to_sym, values: values, exclude: negative }

      # Detect sub-issues prefix (e.g. "sub-issues.status:open") and strip it,
      # marking the qualifier so it can be included/excluded during compilation.
      keyword_str = result[:keyword].to_s
      if keyword_str.start_with?(SUB_ISSUES_PREFIX)
        result[:keyword] = keyword_str.delete_prefix(SUB_ISSUES_PREFIX).to_sym
        result[:sub_issue_filter] = true
      end

      result
    end

    # Parses segments (from extract_top_level_segments) into a flat results array.
    # Group segments are recursively parsed and emitted as { keyword: :GROUP, children: [...] }.
    # Flat segments are parsed with the standard tokenizer.
    private def parse_with_groups(segments, normalizer:, context:)
      results = []
      segments.each do |segment|
        if segment[:type] == :group
          inner_results = parse(segment[:content], normalizer:, context:, enable_groups: true)
          results << { keyword: :GROUP, children: inner_results } unless inner_results.empty?
        else
          flat_content = segment[:content]
          next if flat_content.blank?

          tokens = tokenize(flat_content, normalizer:, context:)
          begin
            raw_results = lex_tokens(tokens)
            results.concat(raw_results)
          rescue QuerySyntaxError
            next
          end
        end
      end
      mark_logical_operators(results)
    end

    # Splits a query string into top-level flat and group segments by scanning for balanced parentheses.
    # Parentheses inside double-quoted or single-quoted strings are ignored.
    # Unmatched closing parentheses are treated as literal characters (depth stays at 0).
    # If nesting exceeds MAX_PAREN_DEPTH, returns a single flat segment with the original query.
    #
    # Example: "is:open (label:bug OR assignee:@me) status:Ready"
    # => [
    #      { type: :flat,  content: "is:open " },
    #      { type: :group, content: "label:bug OR assignee:@me" },
    #      { type: :flat,  content: " status:Ready" }
    #    ]
    private def extract_top_level_segments(query)
      segments = []
      depth = 0
      in_double_quotes = T.let(false, T::Boolean)
      in_single_quotes = T.let(false, T::Boolean)
      group_start = T.let(-1, T.untyped)
      flat_start = T.let(0, T.untyped)

      query.chars.each_with_index do |char, i|
        escaped = i > 0 && query[i - 1] == "\\"
        if char == '"' && !in_single_quotes && !escaped
          in_double_quotes = !in_double_quotes
        elsif char == "'" && !in_double_quotes && !escaped
          in_single_quotes = !in_single_quotes
        elsif !in_double_quotes && !in_single_quotes
          if char == "("
            if depth == 0
              # Only treat as a group start when at position 0 or preceded by whitespace.
              # This prevents splitting keywords that contain parens (e.g. `start-date-(estimate):value`).
              prev_char = i > 0 ? query[i - 1] : nil
              if prev_char.nil? || prev_char.match?(/\s/)
                flat_content = query[flat_start...i]
                segments << { type: :flat, content: flat_content } if flat_content && !flat_content.empty?
                group_start = i + 1
                depth += 1
              end
              # else: treat ( as ordinary flat text — do not change depth
            else
              depth += 1
              # Bail out if nesting is too deep to prevent unbounded recursion.
              if depth > MAX_PAREN_DEPTH
                return [{ type: :flat, content: strip_all_unquoted_parens(query) }]
              end
            end
          elsif char == ")"
            if depth > 0
              depth -= 1
              if depth == 0
                segments << { type: :group, content: query[group_start...i] || "" }
                flat_start = i + 1
              end
            end
          end
        end
      end

      # If an opening paren was never closed, fall back to the original query
      # to avoid duplicating or losing content. Strip only the unmatched
      # parentheses so qualifier values containing parens are preserved.
      if depth > 0
        return [{ type: :flat, content: strip_unmatched_parens(query) }]
      end

      remaining = query[flat_start..]
      segments << { type: :flat, content: remaining } if remaining && !remaining.empty?

      segments
    end

    # Strips only unmatched parentheses from a string while respecting quoted regions.
    # Matched paren pairs and parens inside quotes are preserved.
    private def strip_unmatched_parens(str)
      chars = str.chars
      in_dq = T.let(false, T::Boolean)
      in_sq = T.let(false, T::Boolean)
      stack = T.let([], T::Array[Integer])
      unmatched = T.let(Set.new, T::Set[Integer])

      chars.each_with_index do |ch, i|
        escaped = i > 0 && chars[i - 1] == "\\"
        if ch == '"' && !in_sq && !escaped
          in_dq = !in_dq
        elsif ch == "'" && !in_dq && !escaped
          in_sq = !in_sq
        elsif !in_dq && !in_sq
          if ch == "("
            stack.push(i)
          elsif ch == ")"
            if stack.any?
              stack.pop # matched pair — both parens are preserved
            else
              unmatched.add(i) # unmatched close paren
            end
          end
        end
      end

      # Remaining stack entries are unmatched open parens
      stack.each { |pos| unmatched.add(pos) }

      chars.each_with_index.filter_map { |ch, i| ch unless unmatched.include?(i) }.join
    end

    # Strips all parentheses outside of quoted strings. Used when nesting exceeds
    # MAX_PAREN_DEPTH and we need to flatten the entire query for safe parsing.
    private def strip_all_unquoted_parens(str)
      chars = str.chars
      in_dq = T.let(false, T::Boolean)
      in_sq = T.let(false, T::Boolean)

      chars.each_with_index.filter_map do |ch, i|
        escaped = i > 0 && chars[i - 1] == "\\"
        if ch == '"' && !in_sq && !escaped
          in_dq = !in_dq
          ch
        elsif ch == "'" && !in_dq && !escaped
          in_sq = !in_sq
          ch
        elsif !in_dq && !in_sq && (ch == "(" || ch == ")")
          nil
        else
          ch
        end
      end.join
    end

    # Scans parsed token results for free-text tokens whose sole value is "or" or "and" (case-insensitive),
    # and replaces them with logical operator markers { keyword: :OR } / { keyword: :AND }.
    # Only promotes when there is at least one qualifier or GROUP token in the results,
    # so that pure free-text queries like "or" or "hello or world" are preserved as search terms.
    private def mark_logical_operators(results)
      has_qualifier = results.any? { |r| (r[:keyword] != :_ && r[:keyword] != :OR && r[:keyword] != :AND) || r[:keyword] == :GROUP }
      return results unless has_qualifier

      results.map do |result|
        if result[:keyword] == :_ && result[:values].length == 1
          case result[:values].first&.downcase
          when OR_KEYWORD
            { keyword: :OR }
          when AND_KEYWORD
            { keyword: :AND }
          else
            result
          end
        else
          result
        end
      end
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
