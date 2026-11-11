# typed: true
# frozen_string_literal: true

# This is the base class for batch updating "normalized data" for dependabot alerts records in elasticsearch.
# The normalized data in dependabot alerts records comes from the models in the
# DependabotAlertsNormalizedDataModelsType type alias, each of which can affect multiple alerts in elasticsearch.

# Jobs that subclass this one will batch process RepositoryVulnerabilityAlert records associated with
# a given updated model (e.g. VulnerableVersionRange, Vulnerability, CVEEPSS), updating data associated with that model.

# The job implements common behavior for finding and batching RVAs, logging, and error handling.  Subclasses
# need to implement the following methods:
# - default_batch_size: controls the default number of RVAs processed in each batch
# - job_stats_key: a string used to key metrics in dogstatsd for the job
# - process_item: the main logic for processing each item in the batch

module Search
  module DependabotAlerts
    class BatchUpdateNormalizedDataJob < TimedJob
      abstract!

      queue_as :sync_dependabot_alerts_search_index
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      after_discard { |job, error| job.log_error(error) }

      DependabotAlertsNormalizedDataModelsType = T.type_alias do
        T.any(
          ::VulnerableVersionRange,
          ::Vulnerability,
          ::CVEEPSS
        )
      end
      # Ideally we'd define this as an array of classes and reference the array in
      # DependabotAlertsNormalizedDataModelsType, but Sorbet doesn't like splatting an array
      # into a type alias definition.  So we reverse it and grab the raw types from the type alias instead,
      # which Sorbet also doesn't like but we can silence with T.unsafe.  This seems like the best option
      # to having a single source of truth for the models used in this job instead of two lists.
      DependabotAlertsNormalizedDataModels = T.let(
        T.unsafe(DependabotAlertsNormalizedDataModelsType).aliased_type.types.map(&:raw_type).freeze,
        T::Array[T.class_of(ApplicationRecord::Base)]
      )

      sig { abstract.returns(Integer) }
      def default_batch_size; end

      # The maximum runtime of each job in seconds.
      # Manipulating this timeout determines how many batches get processed per job invocation.
      # Setting a lower value will lead to more frequent job invocations with fewer batches processed per job,
      # which may allow job queue throttling to limit the concurrency of these jobs under high load.
      #
      # Do not set this higher than 5 minutes since "kube… imposes a 5 minute max
      # execution time constraint to cap pod shutdown time"
      # (https://gh.io/background-jobs-best-practices-limit-execution-time).
      sig { override.returns(Float) }
      def timeout_sec
        30.seconds.to_f
      end

      # Returns the alert fields that are used by the job. These fields are plucked from the DB in `fetch_batch`.
      sig { overridable.returns(T::Array[Symbol]) }
      def repository_vulnerability_alert_fields
        [:id]
      end

      sig { override.params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def fetch_batch(*args, offset_id:, **kwargs)
        batch_size = kwargs[:batch_size] || self.default_batch_size

        fields = repository_vulnerability_alert_fields
        batch = repository_vulnerability_alerts_for_model(offset_id).limit(batch_size).pluck(*fields)
        return [] if batch.empty?

        # Transform the rows into hashes like { field1: value1, field2: value2 }
        batch = batch.map { |row| Hash[fields.zip(Array(row))] }

        # Wrap the batch in another array so that it's processed as a single item in #perform.
        [batch]
      end

      # This method is used to determine the new `offset_id`.
      sig { override.params(args: T.untyped, item: T::Array[T::Hash[Symbol, T.untyped]], kwargs: T.untyped).returns(Integer) }
      def item_id(*args, item:, **kwargs)
        return 0 if item.empty?

        last_item = T.must(item.last)
        last_item.fetch(:id) { raise "Alert :id must be included in batch data" }
      end

      sig { overridable.params(error: Exception).void }
      def log_error(error)
        log_tags = {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        }

        Failbot.report(error, log_tags)
        GitHub.logger.error(
          "Dependabot alerts batch updating update error",
          "error.class" => error.class.name,
          "error.message" => error.message,
          **log_tags
        )
        GitHub.dogstats.increment(
          "dependabot_alerts.search.#{job_stats_key}.error",
          tags: metrics_tags + ["error:#{error.class.name}"]
        )
      end

      sig { abstract.returns(String) }
      def job_stats_key; end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge(logging_tags)
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge(logging_tags)
      end

      protected

      sig { returns(DependabotAlertsNormalizedDataModelsType) }
      memoize def updated_model
        kwargs = arguments[0] || {}
        updated_model = kwargs[:updated_model]
        raise ArgumentError, "updated_model argument is required" if updated_model.nil?

        updated_model
      end

      sig { params(result: Symbol, update_count: Integer, started_at: Float).void }
      def log_results(result, update_count, started_at)
        # Metrics reporting to dogstats

        tags = ["result:#{result}"] + metrics_tags
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.#{job_stats_key}.time",
          GitHub::Dogstats.duration(started_at),
          tags: tags
        )
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.#{job_stats_key}.updated_count",
          update_count,
          tags: tags
        )
        GitHub.dogstats.distribution(
          "dependabot_alerts.search.#{job_stats_key}.lag",
          GitHub::Dogstats.duration(T.must(updated_model).updated_at),
          tags: tags
        )
      end

      private

      # Returns a relation of active RepositoryVulnerabilityAlerts for the provided `updated_model`.
      # If offset_id is provided and greater than zero, only returns records with id greater than offset_id.
      sig { params(offset_id: Integer).returns(::ActiveRecord::Relation) }
      def repository_vulnerability_alerts_for_model(offset_id)
        # Find all active RepositoryVulnerabilityAlerts that need to be updated.
        # Inactive RepositoryVulnerabilityAlerts are not pushed to Elasticsearch.
        scope = ::RepositoryVulnerabilityAlert.active

        # ActiveRecord converts all open-ended ranges filtering on the id field into
        # `>=` or `<=` as appropriate for the range.  offset_id is the last id processed in the previous batch,
        # so we need to add 1 to the value to make it work as a `>=` filter.
        scope = scope.where(id: (offset_id + 1)..) if offset_id.positive?

        # Filter to records that are directly associated with the updated model.
        # Set optimizer hints to always use the appropriate index on association id + active,
        # where MySQL may choose a less optimal index if additional fields are plucked
        # via repository_vulnerability_alert_fields.
        case typed_model = updated_model
        when VulnerableVersionRange
          scope = scope.optimizer_hints("INDEX(#{::RepositoryVulnerabilityAlert.quoted_table_name} index_rvas_on_range_and_active)")
                       .where(vulnerable_version_range: typed_model)
        when Vulnerability
          scope = scope.optimizer_hints("INDEX(#{::RepositoryVulnerabilityAlert.quoted_table_name} index_rvas_on_vuln_and_active)")
                       .where(vulnerability: typed_model)
        when CVEEPSS
          vuln = typed_model.vulnerability
          vuln = nil if vuln&.innersource?
          scope = scope.optimizer_hints("INDEX(#{::RepositoryVulnerabilityAlert.quoted_table_name} index_rvas_on_vuln_and_active)")
                       .where(vulnerability: vuln)
        end

        scope.order(id: :asc)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def logging_tags
        case typed_model = updated_model
        when VulnerableVersionRange
          { "gh.vulnerable_version_range.id": typed_model.id }
        when Vulnerability
          { "gh.vulnerability.id": typed_model.id }
        when CVEEPSS
          vuln = typed_model.vulnerability
          { "gh.cve_epss.id": typed_model.id, "gh.vulnerability.id": vuln&.innersource? ? nil : vuln&.id }
        end
      end

      sig { returns(T::Array[String]) }
      def metrics_tags
        ["source:#{updated_model.class.name&.underscore}"]
      end
    end
  end
end
