# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class HandleChangedAdvisoryJob < BatchedJob
    extend T::Sig

    queue_as :security_overview_analytics_handle_changed_advisory

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    use_replicas \
      ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Notify

    BATCH_SIZE = 1000
    WITHDRAW_SOURCE_EVENT = "security_advisory.withdraw"
    UPDATE_SOURCE_EVENT = "security_advisory.update"
    Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

    before_perform do |job|
      vulnerability_id = job.arguments.dig(0, :vulnerability_id)
      vulnerable_version_range_id = job.arguments.dig(0, :vulnerable_version_range_id)

      unless vulnerability_id || vulnerable_version_range_id
        raise ArgumentError, "Either vulnerability_id or vulnerable_version_range_id must be provided."
      end

      if vulnerability_id && vulnerable_version_range_id
        raise ArgumentError, "Only vulnerability_id or vulnerable_version_range_id can be provided."
      end

      source_event = job.arguments.dig(0, :source_event)

      raise ArgumentError, "Must provide source_event." unless source_event

      unless vulnerability_id || source_event != UPDATE_SOURCE_EVENT
        raise ArgumentError, "Must provide vulnerability_id to react to advisory update event."
      end
    end

    sig do
      override.params(
        args: T.untyped,
        offset_item_id: Integer,
        vulnerability_id: T.nilable(Integer),
        vulnerable_version_range_id: T.nilable(Integer),
        kwargs: T.untyped,
      ).returns(T::Array[AlertBatchItem])
    end
    def next_batch(*args, offset_item_id:, vulnerability_id: nil, vulnerable_version_range_id: nil, **kwargs)

      GitHub.logger.info("Fetching next batch of affected alerts", "code.namespace": self.class.name, "code.function": __method__)

      GitHub.dogstats.distribution_time("security_overview_analytics.handle_changed_advisory.fetch_next_batch", tags: all_stats_tags) do
        if SecurityOverviewAnalytics::FeatureFlagHelper.handle_changed_advisory_job_run_two_part_query?
          source_event = arguments.dig(0, :source_event)
          base_rel = alerts_scope(source_event:)

          alert_ids = base_rel
            .then { |rel| vulnerability_id.present? ? rel.where(vulnerability_id:) : rel }
            .then { |rel| vulnerable_version_range_id.present? ? rel.where(vulnerable_version_range_id:) : rel }
            .where("id > ?", offset_item_id)
            .order(:id)
            .limit(BATCH_SIZE)
            .pluck(:id)

          # Scoping to all alerts here helps force the scan on primary key instead of MySQL trying to use a
          # non-optimized cluster index that includes the `active` scope.
          RepositoryVulnerabilityAlert.active_and_inactive
            .where(id: alert_ids)
            .pluck(:id, :repository_id, :number)
            .map { |id, repository_id, number| AlertBatchItem.new(id:, repository_id:, number:) }
        else
          RepositoryVulnerabilityAlert.active_and_inactive
            .then { |rel| vulnerability_id.present? ? rel.where(vulnerability_id:) : rel }
            .then { |rel| vulnerable_version_range_id.present? ? rel.where(vulnerable_version_range_id:) : rel }
            .where("id > ?", offset_item_id)
            .order(:id)
            .limit(BATCH_SIZE)
            .pluck(:id, :repository_id, :number)
            .map { |id, repository_id, number| AlertBatchItem.new(id:, repository_id:, number:) }
        end
      end
    end

    sig { override.params(batch: T::Array[AlertBatchItem], args: T.untyped, source_event: String, vulnerability_id: T.nilable(Integer), kwargs: T.untyped).void }
    def process_batch(batch, *args, source_event:, vulnerability_id: nil, **kwargs)
      return if batch.empty?

      GitHub.logger.info(
        "Processing batch of affected alerts",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.batch_size": batch.size,
        "gh.security_overview_analytics.job.batch_ids": batch.map(&:id),
        "gh.security_overview_analytics.job.is_last_batch": !has_next_batch?(batch, source_event:, vulnerability_id:, **kwargs),
      )

      if source_event == WITHDRAW_SOURCE_EVENT
        withdraw_batch(batch)
      elsif source_event == UPDATE_SOURCE_EVENT
        update_batch(batch, vulnerability_id: T.must(vulnerability_id))
      else
        raise ArgumentError, "Unsupported source_event: #{source_event}"
      end
    end

    sig { override.params(batch: T::Array[AlertBatchItem], args: T.untyped, progress: Integer, options: T.untyped).void }
    def finalize_batch(batch, *args, progress:, **options)
      GitHub.logger.info(
        "Finished handling changed advisory",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.progress": progress,
        "gh.security_overview_analytics.job.batch_size": batch.size,
        "gh.security_overview_analytics.job.batch_ids": batch.map(&:id),
        "gh.security_overview_analytics.job.is_last_batch": !has_next_batch?(batch, progress:, **options),
      )
    end

    private

    sig { params(source_event: String).returns(ActiveRecord::Relation) }
    def alerts_scope(source_event:)
      if source_event == WITHDRAW_SOURCE_EVENT
        # During a withdraw event the alerts are withdrawn by WithdrawRepositoryVulnerabilityAlertsJob,
        # and thus become inactive, before this job runs.
        RepositoryVulnerabilityAlert.active_and_inactive
      else
        RepositoryVulnerabilityAlert.active
      end
    end

    sig { params(batch: T::Array[AlertBatchItem]).void }
    def withdraw_batch(batch)
      batch.group_by(&:repository_id).each do |repository_id, alerts|
        # If we don't have any revisions for this repo in the replicas, then we don't need to touch the primary.
        next unless DependabotAlertRevision.where(repository_id:).exists?

        alert_numbers = alerts.map(&:number)
        DependabotAlertRevision.throttle_writes_with_retry do
          DependabotAlertRevision.where(repository_id:, alert_number: alert_numbers).delete_all
        end
      end
    end

    sig { params(batch: T::Array[AlertBatchItem], vulnerability_id: Integer).void }
    def update_batch(batch, vulnerability_id:)
      vulnerability = Vulnerability.find_by(id: vulnerability_id)
      severity = vulnerability&.severity&.upcase&.to_sym || Event::Severity.lookup(Event::Severity::SEVERITY_UNKNOWN)
      updates = { alert_severity: severity }

      batch.group_by(&:repository_id).each do |repository_id, alerts|
        # If we don't have any revisions for this repo in the replicas, then we don't need to touch the primary.
        next unless DependabotAlertRevision.where(repository_id:).exists?

        alert_numbers = alerts.map(&:number)
        DependabotAlertRevision.throttle_writes_with_retry do
          DependabotAlertRevision.where(repository_id:, alert_number: alert_numbers).update_all(**updates)
        end
      end
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_alerts.vulnerability.id": arguments.dig(0, :vulnerability_id),
        "gh.security_alerts.vulnerable_version_range.id": arguments.dig(0, :vulnerable_version_range_id),
        "gh.security_overview_analytics.source_event": arguments.dig(0, :source_event),
        "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress) || 0,
        "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id) || 0,
        "gh.security_overview_analytics.job.initial_start": arguments.dig(0, :initial_start),
      })
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def failbot_context
      super.merge(**logging_context).merge({ app: "github-security-center" })
    end

    class AlertBatchItem < T::Struct
      const :id, Integer
      const :number, Integer
      const :repository_id, Integer
    end
  end
end
