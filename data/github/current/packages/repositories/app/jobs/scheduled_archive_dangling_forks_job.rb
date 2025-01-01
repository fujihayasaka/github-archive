# typed: true
# frozen_string_literal: true

class ScheduledArchiveDanglingForksJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :archive_dangling_forks

  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    return if GitHub.enterprise?
    ArchiveDanglingForksJob.perform_later
  end
end
