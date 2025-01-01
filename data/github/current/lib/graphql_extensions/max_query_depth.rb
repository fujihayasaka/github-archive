# typed: true
# frozen_string_literal: true

module GraphQLExtensions
  module MaxQueryDepth
    extend T::Helpers
    requires_ancestor { GraphQL::Analysis::AST::MaxQueryDepth }

    def analyze?
      if query.context[:origin] == Platform::ORIGIN_INTERNAL
        GitHub.analyze_internal_graphql?
      else
        if query.context[:operation_id].present?
          return FeatureFlag.vexi.enabled?(:gql_run_analyzers_on_persisted_queries, default: false)
        end
        true
      end
    end

  end
end
