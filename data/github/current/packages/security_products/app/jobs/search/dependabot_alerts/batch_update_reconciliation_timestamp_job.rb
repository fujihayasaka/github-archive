# typed: strict
# frozen_string_literal: true

# This job updates the RepositoryVulnerabilityAlert#search_index_updated_at timestamp to match
# the updated_at timestamp of an associated model in the `updated_model` job argument.  This timestamp is
# used to track the last time that alert data was updated across all normalized data models that make up a single
# dependabot alert (e.g. RepositoryVulnerabilityAlert, VulnerableVersionRange, Vulnerability, CVEEPSS).
# If the timestamp is newer in MySQL than in Elasticsearch, the alert document in Elasticsearch may be out of date.
#
# After all reconciliation timestamps are updated in MySQL, a BatchUpdateElasticsearchJob is enqueued
# to update documents for the updated_model in Elasticsearch.

module Search
  module DependabotAlerts
    class BatchUpdateReconciliationTimestampJob < BatchUpdateNormalizedDataJob
      MAX_THROTTLE_RETRIES = 5
      # A smaller batch size limits the time spent locking rows in the DB per batch.
      BATCH_SIZE = T.let(100, Integer)

      RETRYABLE_ERRORS = [
        ActiveRecord::ConnectionTimeoutError,
        ActiveRecord::QueryCanceled,
      ].freeze

      retry_on(*RETRYABLE_ERRORS)

      sig { override.returns(Integer) }
      def default_batch_size
        BATCH_SIZE
      end

      sig { override.params(args: T.untyped, item: T::Array[T::Hash[Symbol, T.untyped]], kwargs: T.untyped).void }
      def process_item(*args, item:, **kwargs)
        ids = item.map { |row| row[:id] }
        start = GitHub::Dogstats.monotonic_time

        # Update this batch of records in a single SQL statement, filtering out records that do not
        # need an update. As a single all-inclusive SQL statement, this will be an atomic operation
        # at the DB level.

        updated_count = ActiveRecord::Base.connected_to(role: :writing) do
          ::RepositoryVulnerabilityAlert.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            ::RepositoryVulnerabilityAlert.where(id: ids, search_index_updated_at: ...updated_model.updated_at)
              .update_all(search_index_updated_at: updated_model.updated_at)
          end
        end

        log_results(:success, updated_count, start)
      rescue StandardError => e
        log_results(:failure, 0, start)
        raise
      end

      sig { override.params(args: T.untyped, kwargs: T.untyped).void }
      def finalize_sequence(*args, **kwargs)
        T.unsafe(BatchUpdateElasticsearchJob).perform_later(updated_model:)
      end

      sig { override.returns(String) }
      def job_stats_key
        "update_search_index_updated_at"
      end
    end
  end
end
