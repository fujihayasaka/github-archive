# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module DependencyGraph
      class SearchQueryBuilder < ::Search::Query
        RELATIONSHIP_QUALIFIER = "relationship"
        ECOSYSTEM_QUALIFIER = "ecosystem"

        QUALIFIERS = T.let([
          (RELATIONSHIP = :relationship),
          (ECOSYSTEM = :ecosystem)
        ].freeze, T::Array[Symbol])

        VALID_RELATIONSHIPS = T.let(%w[direct transitive inconclusive].freeze, T::Array[String])
        VALID_ECOSYSTEMS = T.let(::DependencyGraph::Ecosystems.supported_labels.freeze, T::Array[String])

        def self.field_list
          [:relationship, :ecosystem].freeze
        end

        def initialize(query:)
          query = sanitize_query(query)
          super({ raw_phrase: query })
        end

        def parsed_query
          @parsed_query ||= self.class.parse(raw_query)
        end

        def qualifier_values(key:)
          parsed_query.select { |component| component.is_a?(Array) && component[0] == key }.map { |component| component[1] }
        end

        def relationship
          values = qualifier_values(key: RELATIONSHIP)
          values.last
        end

        def ecosystem
          values = qualifier_values(key: ECOSYSTEM)
          values.last
        end

        def toggle_ecosystem(ecosystem)
          query = raw_query || ""
          regex = criterion_regex(ECOSYSTEM_QUALIFIER)
          matches = query.scan(regex)

          if matches.any?
            current_ecosystem = matches.first[1] || matches.first[0]
            if current_ecosystem == ecosystem
              query = query.gsub(regex, "").strip
            else
              query = query.gsub(regex, " #{ECOSYSTEM_QUALIFIER}:#{format_spaces(ecosystem)}").strip
            end
          else
            query += " #{ECOSYSTEM_QUALIFIER}:#{format_spaces(ecosystem)}"
          end

          query.strip
        end

        def search_query
          parsed_query.select { |component| component.is_a?(String) }.join(" ")
        end

        def raw_query
          raw_phrase
        end

        private

        # Check if the criterion value contains spaces and wrap it in quotes if it does i.e. "Github Actions"
        def format_spaces(value)
          return "" if value.nil?
          value.include?(" ") ? "\"#{value}\"" : value
        end

        def sanitize_query(query)
          query = remove_negated_criteria(query)
          query = keep_last_occurrence(query, RELATIONSHIP_QUALIFIER)
          query = keep_last_occurrence(query, ECOSYSTEM_QUALIFIER)
          query
        end

        def remove_negated_criteria(query)
          return query unless query

          QUALIFIERS.each do |qualifier|
            query = query.gsub(negated_criterion_regex(qualifier), "").strip
          end

          query
        end

        def keep_last_occurrence(query, criterion)
          return query unless query

          matches = query.scan(criterion_regex(criterion)).flatten.compact

          if matches.length > 0
            last_valid_match = T.let(nil, T.untyped)
            matches.each do |match|
              last_valid_match = match if valid_match?(criterion, match)
            end

            query = query.gsub(criterion_regex(criterion), "").strip
            if last_valid_match
              query += " #{criterion}:#{format_spaces(last_valid_match)}"
            end
          end

          query
        end

        # Regex for criterion. Matches strings like /relationship:direct/ or /ecosystem:"Github Actions"/
        def criterion_regex(criterion)
          /\s?#{criterion}:(?:"([^"]+)"|(\w+))/
        end

        # Regex for negated criterion. Matches strings like /-relationship:direct/ or /-ecosystem:npm/
        def negated_criterion_regex(criterion)
          /\s?-#{criterion}:(?:"([^"]+)"|(\w+))/
        end

        def valid_match?(criterion, match)
          case criterion
          when RELATIONSHIP_QUALIFIER
            VALID_RELATIONSHIPS.include?(match)
          when ECOSYSTEM_QUALIFIER
            VALID_ECOSYSTEMS.include?(match)
          else
            false
          end
        end
      end
    end
  end
end
