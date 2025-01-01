# typed: true
# frozen_string_literal: true

class AuditLogExportJob < ApplicationJob
  queue_as :audit_log_exports
  schedule interval: 1.minute, condition: -> { !GitHub.enterprise? }
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform
    return unless GitHub.flipper[:audit_log_export_job].enabled?

    start = Time.now

    AuditLogWebExport.where({ completed: false, expired: false }).order(created_at: :desc).find_each do |export|
      next unless export_job_enabled?(export.actor, export.subject)
      check_status(export)
    end

    AuditLogGitEventExport.where({ completed: false, expired: false }).order(created_at: :desc).find_each do |export|
      next unless export_job_enabled?(export.actor, export.subject)
      check_status(export)
    end

    GitHub.dogstats.timing_since("audit_log_export_job.total_time", start)
  end

  def export_job_enabled?(actor, subject)
    actor&.feature_enabled?(:audit_log_export_logs) ||
      subject&.feature_enabled?(:audit_log_export_logs)
  end

  def update_export(export, props)
    export.throttle do
      with_write do
        export.update!(props)
      end
    end
  end

  def check_status(export)
    GitHub.dogstats.increment("audit_log_export_job.export",
      tags: ["export_type:#{export.class}"])

    if export.created_at < 24.hours.ago
      GitHub.dogstats.increment("audit_log_export_job.export_expired",
        tags: ["export_type:#{export.class}"])

      return update_export(export, expired: true)
    end

    resp = export.export_status
    if resp[:status] == :STATUS_TYPE_SUCCESSFUL
      success = update_export(export, completed: true, total_chunks: resp[:chunks])
      if success
        AccountMailer.audit_log_download_available(export.actor, export.subject).deliver_later
        GitHub.dogstats.increment("audit_log_export_job.export_completed",
          tags: ["export_type:#{export.class}"])
      end
    else
      if resp[:status] != :STATUS_TYPE_STARTED
        GitHub.dogstats.increment(
          "audit_log_export_job.error",
          tags: ["exception:#{resp}", "export_type:#{export.class}"]
        )
      end
    end
  rescue StandardError => error # rubocop:disable Lint/GenericRescue
    GitHub.dogstats.increment(
      "audit_log_export_job.error",
      tags: ["exception:#{error}", "export_type:#{export.class}"]
    )
  end
end
