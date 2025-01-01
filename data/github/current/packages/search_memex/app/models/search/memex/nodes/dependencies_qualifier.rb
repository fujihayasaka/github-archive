# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class DependenciesQualifier < Qualifier
        include DependenciesValueHelpers

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          unless dependencies_search_enabled?(context)
            # Fall back to full text search when dependencies search is not enabled
            return Nodes::FullTextQuery.new(query_string).compile(context)
          end

          query_clauses = values.map do |query_value|
            compile_dependencies_value_query(slug:, query_value:)
          end.compact

          if negated?
            { bool: { must_not: query_clauses } }
          else
            { bool: { should: query_clauses, minimum_should_match: 1 } }
          end
        end
      end
    end
  end
end
