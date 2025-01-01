# typed: true
# frozen_string_literal: true

class RepositorySetLicenseJob < ApplicationJob
  queue_as :repository_set_license

  RETRYABLE_ERRORS = [
    ActiveRecord::RecordNotUnique,
    ActiveRecord::RecordInvalid,
  ]

  # Retry if race condition occurs due to rapid push events
  retry_on *T.unsafe(RETRYABLE_ERRORS), wait: :polynomially_longer, attempts: 2
  retry_on_dirty_exit

  # Discard the job if the repository is deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  exempt_from_tenant_context_requirement

  def perform(repository)
    with_write { repository.set_licenses }
  end
end
