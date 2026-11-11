# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class DependenciesQualifier < Qualifier
        include DependenciesValueHelpers

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          authorized_values = values.select do |query_value|
            authorized_dependency_reference?(query_value, context.viewer)
          end

          query_clauses = authorized_values.map do |query_value|
            compile_dependencies_value_query(slug:, query_value:)
          end.compact

          if query_clauses.empty?
            # Negated query with no authorized refs should match all (prevents info disclosure)
            return { match_all: {} } if negated?
            return { bool: { must_not: { match_all: {} } } }
          end

          if negated?
            { bool: { must_not: query_clauses } }
          else
            { bool: { should: query_clauses, minimum_should_match: 1 } }
          end
        end

        private

        sig { params(query_value: String, viewer: T.nilable(User)).returns(T::Boolean) }
        def authorized_dependency_reference?(query_value, viewer)
          parsed = GitHub::IssueReferenceParser.parse_nwo_reference(query_value)
          return false unless parsed

          nwo = parsed[:nwo]
          # Allow plain issue references like "#123" (same-repo dependencies)
          return true unless nwo

          repository = Repository.with_name_with_owner(nwo)

          # Allow non-existent repos to avoid disclosing existence of private repos
          return true unless repository

          # Anonymous users can only reference public repos
          return repository.public? unless viewer

          repository.visible_and_readable_by?(viewer)
        end
      end
    end
  end
end
