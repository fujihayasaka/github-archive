# typed: strict
# frozen_string_literal: true

class HydroOrganizationAdvancedSecurityLicenseToggledJob < HydroMessageJob
  queue_as :hydro_security_products_organization_advanced_security_license_toggled

  retry_on_dirty_exit

  sig { void }
  def perform
    organization_id, request_id = message.values_at(
      :organization_id,
      :request_id
    )
    organization_id = T.let(organization_id, Integer)
    org = Organization.new(id: organization_id)
    OrganizationAdvancedSecurityLicenseToggledJob.perform_later(organization_id: organization_id, original_message: message)
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      app: "github-security-center"
    })
  end
end
