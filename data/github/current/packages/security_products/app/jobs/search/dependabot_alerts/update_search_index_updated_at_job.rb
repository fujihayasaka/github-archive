# typed: strict
# frozen_string_literal: true

# This job updates RepositoryVulnerabilityAlert#search_index_updated_at to match
# the updated_at timestamp of an associated model in the `updated_model` job argument.
# The job is built to be idempotent and repeatable, filtering alerts only by their
# associated model.
#
# The job processes records in batches, controlled by the `batch_size` and `batch_count`
# job arguments.  If there are more records to process after the initial batch, the job
# will re-enqueue itself to continue processing the remaining records.
#
# The job also enqueues a BulkUpdateSearchIndexJob for each batch to update the
# corresponding documents in Elasticsearch.

module Search
  module DependabotAlerts
    class UpdateSearchIndexUpdatedAtJob < ApplicationJob
      queue_as :vulnerability_identification

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      RETRYABLE_ERRORS = [
        ActiveRecord::ConnectionTimeoutError,
        ActiveRecord::QueryCanceled,
      ].freeze

      RETRYABLE_ERRORS.each do |error|
        retry_on(error) do |_job, error|
          Failbot.report(error)
        end
      end

      DependabotAlertsBulkUpdateModels = T.type_alias do
        T.any(
          ::VulnerableVersionRange,
          ::Vulnerability,
          ::ScopedVulnerability,
          ::CVEEPSS
        )
      end

      # Batch size controls the size for individual reads and writes from MySQL,
      # to limit the max cost per DB query
      BATCH_SIZE = T.let(1000, Integer)

      # Write batch size controls the size of individual update_all writes to MySQL,
      # to limit lock contention and transaction size for large batches
      WRITE_BATCH_SIZE = T.let(100, Integer)

      # Batch count controls the number of batches processed in a single job execution,
      # to limit the max runtime per job
      BATCH_COUNT = T.let(5, Integer)

      sig do
        params(
          updated_model: DependabotAlertsBulkUpdateModels,
          start: Integer,
          batch_size: Integer,
          batch_count: Integer
        ).void
      end
      def perform(updated_model:, start: 0, batch_size: BATCH_SIZE, batch_count: BATCH_COUNT)
        repository_vulnerability_alerts_for_model(updated_model, start)
          .in_batches(of: batch_size, start: start)
          .take(batch_count)
          .each do |batch|
            # in_batches always returns a relation with a where clause on id,
            # so we can use that to pull the ids for this batch instead of plucking them with another query.
            ids = Array(batch.where_values_hash["id"])
            ids.each_slice(WRITE_BATCH_SIZE) do |ids_slice|
              update_start_time = GitHub::Dogstats.monotonic_time
              # Update this batch of records in a single SQL statement, filtering out records that do not
              # need an update. As a single all-inclusive SQL statement, this will be an atomic operation
              # at the DB level.

              updated_count = ActiveRecord::Base.connected_to(role: :writing) do
                RepositoryVulnerabilityAlert.where(id: ids, search_index_updated_at: ...updated_model.updated_at)
                  .update_all(search_index_updated_at: updated_model.updated_at)
              end

              duration = GitHub::Dogstats.duration(update_start_time)
              logging_tags = logging_tags(updated_model, (ids_slice.first..ids_slice.last))
              metrics_tags = ["source:#{updated_model.class.name&.underscore}"]
              log_results(updated_model, updated_count, duration, logging_tags, metrics_tags)

              # Update the corresponding documents in Elasticsearch separately for the batch that was just processed
              BulkUpdateSearchIndexJob.perform_later(
                filters: { id: ids_slice },
                attributes: updated_model.dependabot_alert_fields,
                updated_at: updated_model.updated_at,
                log_tags: logging_tags,
                stats_tags: metrics_tags
              )

              start = T.let(ids_slice.last, Integer) + 1
            end
          end

        # If there are any additional records that need to be updated after the current set
        # of batches have finished, re-enqueue the job to process additional records
        if repository_vulnerability_alerts_for_model(updated_model, start).any?
          self.class.perform_later(updated_model:, start:, batch_size:, batch_count:)
        end
      end

      private

      sig do
        params(
          updated_model: DependabotAlertsBulkUpdateModels,
          update_count: Integer,
          duration: Float,
          logging_tags: T::Hash[T.any(String, Symbol), T.untyped],
          metrics_tags: T::Array[String]
        ).void
      end
      def log_results(updated_model, update_count, duration, logging_tags, metrics_tags)
        # Metrics reporting to dogstats
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.update_search_index_updated_at.time",
          duration,
          tags: metrics_tags
        )
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.update_search_index_updated_at.updated_count",
          update_count,
          tags: metrics_tags
        )
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.update_search_index_updated_at.lag",
          GitHub::Dogstats.duration(updated_model.updated_at),
          tags: metrics_tags
        )
        GitHub.logger.info(
          "Bulk updated dependabot alerts search_index_updated_at timestamp",
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "updated_count" => update_count,
          "duration" => duration,
          **logging_tags
        )
      end

      # Returns a relation of active RepositoryVulnerabilityAlerts for the provided `updated_model`.
      sig do
        params(
          updated_model: DependabotAlertsBulkUpdateModels,
          start: Integer
        ).returns(::ActiveRecord::Relation)
      end
      def repository_vulnerability_alerts_for_model(updated_model, start)
        # Find all active RepositoryVulnerabilityAlerts that need to be updated.
        # Inactive RepositoryVulnerabilityAlerts are not pushed to Elasticsearch,
        # and any changes to an alert to make them active will automatically bump
        # that alert's search_index_updated_at timestamp.
        scope = ::RepositoryVulnerabilityAlert.active
        scope = scope.where(id: start..) if start.positive?

        # Filter to records that are directly associated with the updated model
        case updated_model
        when VulnerableVersionRange
          scope = scope.where(vulnerable_version_range: updated_model)
        when Vulnerability, ScopedVulnerability
          scope = scope.where(vulnerability: updated_model)
        when CVEEPSS
          scope = scope.where(vulnerability: updated_model.vulnerability)
        end

        scope
      end

      sig do
        params(
          updated_model: DependabotAlertsBulkUpdateModels,
          id_range: T::Range[Integer],
        ).returns(T::Hash[T.any(String, Symbol), T.untyped])
      end
      def logging_tags(updated_model, id_range)
        model_tags = case updated_model
        when VulnerableVersionRange
          { "gh.vulnerable_version_range.id" => updated_model.id }
        when Vulnerability, ScopedVulnerability
          { "gh.vulnerability.id" => updated_model.id }
        when CVEEPSS
          { "gh.cve_epss.id" => updated_model.id, "gh.vulnerability.id" => T.must(updated_model.vulnerability).id }
        end

        model_tags.merge!("alert_id_range" => id_range.to_s)
      end
    end
  end
end
