# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module DbTracer
      MAX_DB_CALLS = GitHub::Config::RequestLimits::GRAPHQL_DATABASE_BUDGET_MAX
      include Kernel

      # This is called in the _initial_ resolve call, before any promises are returned.
      def execute_field(field:, query:, ast_node:, arguments:, object:)
        enforce_db_call_limit_and_execute(query: query) { super }
      end

      # This is called in the lazy execution phase, after promises are returned.
      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        enforce_db_call_limit_and_execute(query: query) { super }
      end

      private

      def enforce_db_call_limit_and_execute(query:)
        context = query.context

        # Skip for persisted queries or if the query itself is internal
        is_persisted_query = context[:operation_id].present?
        is_internal_query = context[:target] == :internal
        return yield if is_persisted_query || is_internal_query

        query_tracker = context[:query_tracker]
        if query_tracker.nil?
          # allow field execution to proceed if no query tracker is available
          return yield
        end

        db_count = query_tracker.mysql_count
        db_call_budget_exceeded = db_count > MAX_DB_CALLS

        # Allow field execution as normal if db_count is below the maximum allowed
        return yield unless db_call_budget_exceeded

        oauth_app = context[:oauth_app]
        integration = context[:integration]
        actor = context[:actor]

        excluded_from_hard_limit = FeatureFlag.vexi.enabled?(:bypass_graphql_database_hard_limit, actor, oauth_app, integration, default: false)
        hard_limit_enabled = !excluded_from_hard_limit && FeatureFlag.vexi.enabled?(:graphql_database_hard_limit, actor, oauth_app, integration, default: false)

        # Allow field execution as normal if FF is off.
        return yield unless hard_limit_enabled

        GitHub.dogstats.increment("platform.query.db_calls_exceeded")

        raise Platform::Errors::ResourceLimitsExceeded.new
      end
    end
  end
end
