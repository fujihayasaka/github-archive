# typed: true
# frozen_string_literal: true

# This job is responsible for refreshing the auto-dismissal state on Dependabot Alerts that already exist.
#
class RefreshDependabotAlertsStateJob < BatchedJob
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

  def process_batch(batch, vulnerable_version_range_id: nil, **kwargs)
    batch.each do |repository_id|
      repository = Repositories::Public.find_active(repository_id)
      next unless repository&.vulnerability_alerts_enabled?

      alerts = repository.repository_vulnerability_alerts.where(vulnerable_version_range_id:)
      alerts.find_each do |alert|
        with_write do
          alert.auto_dismiss_or_reopen(reason: :alert_updated)
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
end
