# typed: strict
# frozen_string_literal: true

class DestroyEnterpriseInstallationJob < ApplicationJob
  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0].id
  }

  queue_as :destroy_enterprise_installation

  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::RecordNotFound

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(enterprise_installation: EnterpriseInstallation).void }
  def perform(enterprise_installation)
    with_write { enterprise_installation.destroy }
  end
end
