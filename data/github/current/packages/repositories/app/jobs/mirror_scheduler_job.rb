# typed: true
# frozen_string_literal: true

class MirrorSchedulerJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :mirrors

  schedule interval: 1.minute, condition: -> { !GitHub.enterprise? }

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 10

  def perform
    Mirror.schedule_pending(BATCH_SIZE)
  end
end
