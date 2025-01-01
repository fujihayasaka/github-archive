# typed: strict
# frozen_string_literal: true

class HydroOrganizationAddJob < OrganizationHydroMessageJob
  queue_as :hydro_security_products_organization_add

  retry_on_dirty_exit

  # This will allow the job to retry for about 1 hour
  MAX_RETRIES_NOT_FOUND = 8

  T.unsafe(self).retry_on OrganizationNotFoundError, delay: :polynomially_longer, max_retries: MAX_RETRIES_NOT_FOUND do
    # If the organization is nil, we have already retried the job the maximum number of times
    # and we should stop retrying the job.
    GitHub.logger.info(
      "Organization not found after #{MAX_RETRIES_NOT_FOUND} retries, skipping job."
    )
    # Return true to stop reporting exception
    true
  end

  sig { void }
  def perform
    OrganizationAddJob.perform_later(organization_id: organization_id, original_message: message, original_message_envelope: original_message_envelope)
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      app: "github-security-center"
    })
  end
end
