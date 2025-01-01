# typed: true
# frozen_string_literal: true
module Platform
  module Analyzers
    class QueryComplexity < GraphQL::Analysis::AST::QueryComplexity
      def analyze?
        return false unless GitHub.flipper[:gql_run_native_analyzers].enabled?

        if query.context[:origin] == Platform::ORIGIN_INTERNAL
          GitHub.analyze_internal_graphql?
        else
          if query.context[:operation_id].present?
            return GitHub.flipper[:gql_run_analyzers_on_persisted_queries].enabled?
          end
          true
        end
      end

      def result
        complexity = super
        GitHub.dogstats.distribution("platform.analyzers.query_complexity.complexity", complexity, tags: query.context[:query_tracker].dog_tags)
      end
    end
  end
end
