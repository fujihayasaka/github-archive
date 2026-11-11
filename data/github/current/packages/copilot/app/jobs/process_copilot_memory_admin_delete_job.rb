# typed: strict
# frozen_string_literal: true

class ProcessCopilotMemoryAdminDeleteJob < CopilotJob
  queue_as :copilot_memory_admin_deletes

  retry_on_dirty_exit do |job, error|
    job.dirty_exit_failed!(error)
  end

  resolve_tenant_context do |status_id|
    status = Copilot::MemoryAdminDelete.status(status_id)
    owner = Copilot::MemoryAdminDelete.owner_from_status(status) if status
    Copilot::MemoryAdminDelete.tenant_for_owner(owner) if owner
  end

  sig { params(status_id: String).void }
  def perform(status_id)
    status = Copilot::MemoryAdminDelete.status(status_id)
    return unless status
    return if status.success? || status.error?

    lease_token = Copilot::MemoryAdminDelete.acquire_lease(status_id)
    return unless lease_token

    should_reenqueue = T.let(false, T::Boolean)
    begin
      should_reenqueue = Copilot::MemoryAdminDelete.process(status)
    rescue Aqueduct::Worker::JobKilled
      raise
    rescue StandardError => error
      Copilot::MemoryAdminDelete.failed!(status, error: error, report: false)
      raise
    ensure
      Copilot::MemoryAdminDelete.release_lease(status_id, token: lease_token)
    end

    reenqueue!(status_id) if should_reenqueue
  end

  sig { params(error: Exception).void }
  def dirty_exit_failed!(error)
    status_id = arguments.first.to_s
    return if status_id.blank?

    Copilot::MemoryAdminDelete.dirty_exit_failed!(status_id, error: error)
  end

  private

  sig { params(status_id: String).void }
  def reenqueue!(status_id)
    self.class.perform_later(status_id)
  rescue StandardError => error
    status = Copilot::MemoryAdminDelete.status(status_id)
    Copilot::MemoryAdminDelete.failed!(status, error: error, report: false) if status
    raise
  end
end
