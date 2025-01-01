# typed: true
# frozen_string_literal: true

module Audit
  module Driftwood
    class AsyncQuery
      include Scientist
      extend Scientist
      extend Forwardable

      class DriftwoodQueryNotPermitted < StandardError; end

      def initialize
        @client = GitHub.driftwood_client_v1
      end

      # Tell Driftwood to start a web event export for a given organization, user or business
      def start(query_id:, phrase:, per_page:, after:, before:, feature_flags: [])

        resp = @client.async_stafftools_query_start(
          query_id: query_id,
          phrase: phrase,
          per_page: per_page,
          after: after,
          before: before,
          feature_flags: feature_flags,
        ).execute

        { operation_id: resp.operation_id, warnings: resp.warnings }
      end

      # Query Driftwood to check whether or not a export job is complete, i.e: don't fetch results
      def check_status(operation_id:, feature_flags:)
        resp = @client.async_stafftools_query_check_status(
          operation_id: operation_id,
          feature_flags: feature_flags,
        ).execute

        { completed: resp.completed, warnings: resp.warnings }
      end

      # Query Driftwood to fetch the results of an export job
      def fetch_results(query_id:, per_page:, after:, before:, feature_flags: [])
        resp = @client.async_stafftools_query_fetch_results(
          query_id: query_id,
          per_page: per_page,
          after: after,
          before: before,
          feature_flags: feature_flags,
        ).execute

        {
          results: resp.results,
          total_count: resp.total_count,
          took: resp.took,
          after: resp.after,
          before: resp.before,
          warnings: resp.warnings,
        }
      end
    end
  end
end
