# typed: true
# frozen_string_literal: true

require_relative "../../models/security_center/k_v"

module SecurityCenter
  class AdvisoryChangeHandlerJob < BatchedJob
    queue_as :security_center_advisory_change
    retry_on_dirty_exit

    BATCH_SIZE = 1000

    before_enqueue do |job|
      vulnerability_id = job.arguments.dig(0, :vulnerability_id)
      vulnerable_version_range_id = job.arguments.dig(0, :vulnerable_version_range_id)

      if vulnerability_id.nil? && vulnerable_version_range_id.nil?
        raise ArgumentError, "Either vulnerability_id or vulnerable_version_range_id must be provided."
      end
    end

    around_enqueue do |job, block|
      vulnerability_id = job.arguments.dig(0, :vulnerability_id)
      vulnerable_version_range_id = job.arguments.dig(0, :vulnerable_version_range_id)
      kv_key = "#{self.class.name&.underscore}:#{vulnerability_id}_#{vulnerable_version_range_id}"
      session_id = job.arguments.first&.dig(:session_id)

      if session_id.nil?
        # a new session always interrupts anything running
        session_id = SecureRandom.uuid
        job.arguments.first.merge!(session_id: session_id)

        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.set(kv_key, session_id, expires: 24.hours.from_now)
        end

        next block.call
      end

      # session_id param exists; this is a continuation job

      lock_value = SecurityCenter::KV.store.get(kv_key).value { nil }
      if lock_value == session_id
        # We still own this lock; continue
        next block.call
      end

      if lock_value.present?
        # Another session has stolen the lock; report and abort
        GitHub.dogstats.increment("security_center.security_advisory_update.interrupted.count", tags: job.all_stats_tags + ["reason:conflict"])
        next
      end

      # This should be impossible. If this is a continuation job, then either we own the lock
      # or someone stole it from under us. Report for investigation.
      GitHub.dogstats.increment("security_center.security_advisory_update.interrupted.count", tags: job.all_stats_tags + ["reason:missing_lock"])
      Failbot.report(StandardError.new("Session lock does not exist."), job.failbot_context)
    end

    def next_batch(
      *args,
      vulnerability_id: nil,
      vulnerable_version_range_id: nil,
      source_event: "",
      offset_item_id:,
      **kwargs
    )
      base_rel = alerts_scope(source_event: source_event)
      base_rel = base_rel.where(vulnerable_version_range_id: vulnerable_version_range_id) if vulnerable_version_range_id.present?
      base_rel = base_rel.where(vulnerability_id: vulnerability_id) if vulnerability_id.present?

      base_rel
        .where("id > ?", offset_item_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .pluck(:id)
    end

    def process_batch(batch, *args, source_event: nil, **kwargs)
      repo_ids = RepositoryVulnerabilityAlert.active_and_inactive.where(id: batch).pluck(:repository_id).uniq

      Repository.includes(:owner).org_owned.where(id: repo_ids).each do |repo|
        ::SecurityCenter::RepositorySyncJob.perform_later(
          repository_id: repo.id,
          feature_type: "dependabot_alerts",
          source_event: source_event || "security_advisory.changed"
        )
      end
    end

    def next_batch_offset_item_id(batch, *args, **kwargs)
      batch.max
    end

    protected

    def stats_tags
      tags = []
      source_event = arguments.dig(0, :source_event)
      tags << "source_event:#{source_event}" if source_event.present?
      tags
    end

    def logging_context
      super.merge({
        "gh.security_alerts.vulnerability.id": arguments.dig(0, :vulnerability_id),
        "gh.security_alerts.vulnerable_version_range.id": arguments.dig(0, :vulnerable_version_range_id),
        "gh.security_center.source_event": arguments.dig(0, :source_event),
        "gh.security_center.job.offset_item_id": arguments.dig(0, :offset_item_id),
        "gh.security_center.job.initial_start": arguments.dig(0, :initial_start),
        "gh.security_center.job.progress": arguments.dig(0, :progress),
      })
    end

    def failbot_context
      super.merge({
        app: "github-security-center",
        "gh.security_alerts.vulnerability.id": arguments.dig(0, :vulnerability_id),
        "gh.security_alerts.vulnerable_version_range.id": arguments.dig(0, :vulnerable_version_range_id),
        "gh.security_center.job.session_id": arguments.dig(0, :session_id),
      })
    end

    private

    def alerts_scope(source_event:)
      if source_event == "security_advisory.withdraw"
        # During a withdraw event the alerts are withdrawn by WithdrawRepositoryVulnerabilityAlertsJob,
        # and thus become inactive, before this job runs.
        RepositoryVulnerabilityAlert.active_and_inactive
      else
        RepositoryVulnerabilityAlert
      end
    end
  end
end
