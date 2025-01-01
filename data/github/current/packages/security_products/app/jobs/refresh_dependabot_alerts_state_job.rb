# typed: true
# frozen_string_literal: true

# This job is responsible for refreshing the auto-dismissal state on Dependabot Alerts that already exist.
#
class RefreshDependabotAlertsStateJob < BatchedJob
  include GitHub::Memoizer

  queue_as :vulnerability_identification

  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 10

  exempt_from_tenant_context_requirement

  before_enqueue do |job|
    vulnerable_version_range_id = job.arguments.dig(0, :vulnerable_version_range_id)

    if vulnerable_version_range_id.nil?
      raise ArgumentError, "A vulnerable_version_range_id must be provided."
    end
  end

  def process_batch(batch, vulnerable_version_range_id: nil, changes: nil, **kwargs)
    batch.each do |repository_id|
      repository = Repositories::Public.find_active(repository_id)
      next unless repository&.vulnerability_alerts_enabled?

      alerts = repository.repository_vulnerability_alerts.where(vulnerable_version_range_id:)
      alerts.find_each do |alert|
        with_write do
          alert.auto_dismiss_or_reopen(reason: :alert_updated)
        end
        if instrument_vulnerability_update? && changes.present?
          GitHub.instrument("repository_vulnerability_alert.vulnerability_update", {
            action: changes.include?("severity") ? "severity_change" : "vulnerability_metadata_change",
            repo_id: alert.repository_id,
            alert_id: alert.id,
            alert_number: alert.number,
            severity: alert.vulnerable_version_range&.vulnerability&.severity,
            vulnerable_version_range_id: alert.vulnerable_version_range_id,
            vulnerability_id: alert.vulnerability_id,
            ghsa_id: alert.vulnerable_version_range&.vulnerability&.ghsa_id,
          })
        end
      end

      alerts.select(&:candidate_for_pull_request?).each do |alert|
        Dependabot::RepositoryVulnerabilityCreatedJob.enqueue(alert)
      end
    end
  end

  def next_batch(vulnerable_version_range_id: nil, offset_item_id: 0, **kwargs)
    if vulnerable_version_range_id.nil?
      raise ArgumentError, "Must specify a vulnerable_version_range_id"
    end

    RepositoryVulnerabilityAlert.without_default_scope
      .where(vulnerable_version_range_id: vulnerable_version_range_id)
      .where("repository_id > ?", offset_item_id)
      .order(:repository_id)
      .limit(BATCH_SIZE)
      .distinct
      .pluck(:repository_id)
  end

  def next_batch_offset_item_id(batch, *args, **options)
    batch.max
  end

  private

  memoize def instrument_vulnerability_update?
    ::SecurityOverviewAnalytics::FeatureFlagHelper.instrument_vulnerability_update_events?
  end
end
