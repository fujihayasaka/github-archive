# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class StateQualifier < Qualifier
        include StateValueHelpers
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          result = T.let({}, T::Hash[T.untyped, T.untyped])

          values.each do |query_value|
            query_clauses = []
            case query_value
            when "draft"
              query_clauses = compile_draft_content_query
            when "closed"
              # For feature parity with legacy project search, we need to include both 'closed' and 'merged' content
              # states when the user queries for 'closed'.
              query_clauses << compile_content_state_query(content_state: query_value)
              query_clauses << compile_content_state_query(content_state: "merged")
            when "open", "merged"
              query_clauses << compile_content_state_query(content_state: query_value)
            end

            clause_key = clause_occurrence_type(query_clauses.count)
            result[clause_key] = result.fetch(clause_key, []) + query_clauses
          end

          result[:minimum_should_match] = 1 if result[:should].present?

          { bool: result }
        end

        # Use the correct occurrence type in the query clause for the given query clause(s)
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html for more details.
        sig { params(query_clause_count: Integer).returns(Symbol) }
        private def clause_occurrence_type(query_clause_count)
          if negated?
            :must_not
          elsif values.one? && query_clause_count == 1
            :must
          else
            # When there are multiple values, or a single value maps to multiple clauses,
            # we need to use the 'should' clause and set the minimum_should_match to 1.
            :should
          end
        end
      end
    end
  end
end
