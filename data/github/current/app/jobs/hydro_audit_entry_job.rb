# typed: true
# frozen_string_literal: true

class HydroAuditEntryJob < ApplicationJob
  queue_as :audit_logs
  retry_on_dirty_exit

  class HydroPublishError < StandardError; end
  retry_on(HydroPublishError, wait: :polynomially_longer, attempts: 20)

  def perform(hydro_message, **options)
    result = GitHub.sync_hydro_publisher.publish(hydro_message, **options)
    if result.success?
      GitHub.dogstats.increment("hydro_audit_entry_job.success")
    else
      GitHub.dogstats.increment("hydro_audit_entry_job.failure")
      raise HydroPublishError, "Failed to publish audit entry to Hydro: #{result.error_message}"
    end
  end
end
