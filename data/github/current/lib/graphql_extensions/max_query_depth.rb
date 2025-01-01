# typed: false
# frozen_string_literal: true

module GraphQLExtensions
  module MaxQueryDepth
    def analyze?
      if query.context[:origin] == Platform::ORIGIN_INTERNAL
        GitHub.analyze_internal_graphql?
      else
        if query.context[:operation_id].present?
          return GitHub.flipper[:gql_run_analyzers_on_persisted_queries].enabled?
        end
        true
      end
    end
  end
end
