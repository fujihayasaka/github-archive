# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class QueryParser
        extend T::Sig
        include GitHub::Memoizer

        CUSTOM_PROPERTIES_PREFIX = "props."

        sig { returns(String) }; attr_reader :original_query_string
        sig { returns(T::Hash[String, T::Array[String]]) }; attr_reader :parsed_query

        sig { params(query_string: String).void }
        def initialize(query_string = "")
          @original_query_string = query_string

          # Initialize parsed_query to the result of parsing the query string.
          @parsed_query = T.let(parse_original_query_string.each { |k, v| k.freeze; v.each(&:freeze).freeze }.freeze, T::Hash[String, T::Array[String]])
        end

        sig { returns(T::Array[String]) }
        def get_unqualified_values
          parsed_query.fetch(unqualified_key, [])
        end

        sig { params(qualifier: String).returns(T::Array[String]) }
        def get_qualified_values(qualifier)
          parsed_query.fetch(qualifier, [])
        end

        sig { params(qualifier: String, qualifier_alias: T.nilable(String)).returns([T::Array[String], T::Array[String]]) }
        def get_positive_and_negative_qualified_values(qualifier, qualifier_alias: nil)
          positive_qualifier = qualifier.delete_prefix(negated_qualifier_prefix)
          negative_qualifier = negate_qualifier(qualifier)

          # When qualifier alias provider, attempt to fetch values with alias only if default key does not exist.
          # This means that we ignore the aliases when default key presents since we do not support usages of having duplicated qualifers.
          unless qualifier_alias.nil? || has_qualified_value?(positive_qualifier) || has_qualified_value?(negative_qualifier)
            positive_qualifier = qualifier_alias.delete_prefix(negated_qualifier_prefix)
            negative_qualifier = negate_qualifier(qualifier_alias)
          end

          [get_qualified_values(positive_qualifier), get_qualified_values(negative_qualifier)]
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        memoize def custom_properties
          parsed_query
            .select { |qualifier, _| qualifier.delete_prefix(negated_qualifier_prefix).start_with?(CUSTOM_PROPERTIES_PREFIX) }
            .transform_keys do |qualifier|
              is_negated = qualifier.start_with?(negated_qualifier_prefix)
              new_qualifier = qualifier.delete_prefix(negated_qualifier_prefix).delete_prefix(CUSTOM_PROPERTIES_PREFIX)
              new_qualifier = negate_qualifier(new_qualifier) if is_negated
              new_qualifier
            end
        end

        sig { returns(String) }
        memoize def custom_properties_string
          custom_properties
            .reduce([]) do |acc, (qualifier, values)|
              is_negated = qualifier.start_with?(negated_qualifier_prefix)
              new_qualifier = qualifier.delete_prefix(negated_qualifier_prefix)
              new_qualifier = "#{CUSTOM_PROPERTIES_PREFIX}#{new_qualifier}"
              new_qualifier = negate_qualifier(new_qualifier) if is_negated

              output_value = values.map { |value| ::Search::ParsedQuery.encode_value(value) }.join(",")

              acc << "#{new_qualifier}:#{output_value}"
              acc
            end
            .join(" ")
        end

        sig { returns(String) }
        def to_s
          split_on_delimiter(original_query_string, " ")
            .reduce([]) do |acc, segment|
              key, values = process_segment(segment)

              if key && values
                next acc unless parsed_query.key?(key)
                acc << "#{key}:#{stringfy_values(values)}"
              elsif parsed_query.fetch(unqualified_key, []).include?(segment)
                acc << segment
              end

              acc
            end
            .join(" ")
        end

        sig { returns(QueryParser) }
        def reverse_negated_prefix
          new_query = split_on_delimiter(original_query_string, " ")
            .reduce([]) do |acc, segment|
              key, values = process_segment(segment)

              # unqualified values are dropped as they are not supported with negation
              next acc unless key && values
              next acc unless parsed_query.key?(key)

              key = if key.start_with?(negated_qualifier_prefix)
                key.delete_prefix(negated_qualifier_prefix)
              else
                "#{negated_qualifier_prefix}#{key}"
              end
              acc << "#{key}:#{stringfy_values(values)}"
            end
            .join(" ")
          QueryParser.new(new_query)
        end

        sig { returns(String) }
        def canonicalize
          parsed_query
            .sort_by { |qualifier, _| qualifier }
            .map do |qualifier, values|
              next if values.empty?
              values_string = values.sort.join(",")
              qualifier == unqualified_key ? values_string : "#{qualifier}:#{values_string}"
            end
            .compact
            .join(" ")
        end

        private

        sig { overridable.returns(String) }
        memoize def unqualified_key
          "_unqualified_keys"
        end

        sig { overridable.returns(T::Boolean) }
        def preserve_case
          false
        end

        sig { overridable.returns(String) }
        def negated_qualifier_prefix
          "-"
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def parse_original_query_string
          split_on_delimiter(original_query_string, " ").reduce({ unqualified_key => [] }) do |acc, segment|
            key, values = process_segment(segment)

            if values
              acc[key] = values
            else
              acc[unqualified_key] << segment
            end

            acc
          end
        end

        sig { params(segment: String).returns([T.nilable(String), T.nilable(T::Array[String])]) }
        def process_segment(segment)
          empty_response = [nil, nil]

          return empty_response unless segment.include?(":")
          return empty_response if segment.start_with?('"') && segment.end_with?('"')

          key, values_str = segment.split(":", 2)
          return empty_response if key.nil? || values_str.nil?

          new_values = split_on_delimiter(values_str, ",")
            .map do |value|
              value_without_extra_quotes = value.gsub(/(^"|"$)/, "")
              convert_case_value(
                value_without_extra_quotes,
                (
                  key == "tool" ||
                  key == negate_qualifier("tool") ||
                  key.start_with?(CUSTOM_PROPERTIES_PREFIX) ||
                  key.start_with?(negate_qualifier(CUSTOM_PROPERTIES_PREFIX)) ||
                  preserve_case
                )
              )
            end

          [key, new_values]
        end

        # Split the query string into unqualified and qualified segments at the provided delimiter.
        sig { params(value: String, delimiter: String).returns(T::Array[String]) }
        def split_on_delimiter(value, delimiter)
          # Regex breakdown:
          #
          # Regexp.escape(delimiter)  : The delimiter to split on.
          #
          # (?= ... )                 : Positive lookahead to check if a pattern matches.
          #                             If the pattern matches, the delimiter is a match.
          #
          # (?:[^"]*"[^"]*")*         : The pattern to determine if we're looking at a qualified segment.
          #                             This takes into account the possibility for quoted values.
          #
          # [^"]*                     : After the last pair of quotes, find remaining non-quote characters.
          #
          # $                         : End of string.
          regex = Regexp.new(Regexp.escape(delimiter) + '(?=(?:[^"]*"[^"]*")*[^"]*$)')
          value.split(regex)
        end

        sig { params(value: String, preserve_case: T::Boolean).returns(String) }
        def convert_case_value(value, preserve_case)
          preserve_case ? value : value.downcase
        end

        sig { params(values: T::Array[String]).returns(String) }
        def stringfy_values(values)
          values.map { |value| value.include?(" ") ? "\"#{value}\"" : value }.join(",")
        end

        sig { params(qualifier: String).returns(String) }
        def negate_qualifier(qualifier)
          if qualifier.start_with?(negated_qualifier_prefix)
            qualifier
          else
            "#{negated_qualifier_prefix}#{qualifier}"
          end
        end

        sig { params(qualifier: String).returns(T::Boolean) }
        def has_qualified_value?(qualifier)
          parsed_query.has_key?(qualifier)
        end
      end
    end
  end
end
