# typed: true
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryDepth < GraphQL::Analysis::AST::QueryDepth
      def analyze?
        return false unless ::FeatureFlag.vexi.enabled?(:gql_run_native_analyzers, default: false) || ::FeatureFlag.vexi.enabled?(:gql_run_query_depth_analyzer, default: false)

        if query.context[:origin] == Platform::ORIGIN_INTERNAL
          GitHub.analyze_internal_graphql?
        else
          if query.context[:operation_id].present?
            return ::FeatureFlag.vexi.enabled?(:gql_run_analyzers_on_persisted_queries, default: false)
          end
          true
        end
      end

      def result
        depth = super
        query.context[:query_depth] = depth

        if ::FeatureFlag.vexi.enabled?(:gql_run_native_analyzers, default: false)
          GitHub.dogstats.distribution("platform.analyzers.query_depth.depth", depth, tags: query.context[:query_tracker].dog_tags)
        end
      end
    end
  end
end
