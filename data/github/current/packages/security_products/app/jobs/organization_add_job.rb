# typed: strict
# frozen_string_literal: true

class OrganizationAddJob < AbstractOrganizationChangeFanoutJob
  queue_as :security_products_organization_add

  retry_on_dirty_exit

  MAX_RETRIES_NOT_FOUND = 8

  retry_on OrganizationNotFoundError, wait: :polynomially_longer, attempts: MAX_RETRIES_NOT_FOUND do |job, _error|
    # If the organization is nil, we have already retried the job the maximum number of times
    # and we should stop retrying the job.
    GitHub.logger.info("Organization not found after #{job.executions} retries, skipping job.")
  end

  sig { params(repository_id: Integer).void }
  def process_repository(repository_id)
    GlobalInstrumenter.instrument("enterprise_account.organization_add_per_repository", {
      repository_id: repository_id,
      organization_add_envelope: arguments.dig(0, :original_message_envelope),
    })
  end

  protected

  sig { returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.security_products.job.source_event": "organization_add",
    })
  end

  sig { returns(T.untyped) }
  def failbot_context
    super.merge({
      "gh.security_products.job.source_event": "organization_add",
    })
  end
end
