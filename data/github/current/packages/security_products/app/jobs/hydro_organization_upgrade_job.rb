# typed: strict
# frozen_string_literal: true

class HydroOrganizationUpgradeJob < OrganizationHydroMessageJob
  queue_as :hydro_security_products_organization_upgrade

  retry_on_dirty_exit

  sig { void }
  def perform
    OrganizationUpgradeJob.perform_later(organization_id: organization_id, original_message: message, original_message_envelope: original_message_envelope)
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      app: "github-security-center"
    })
  end
end
