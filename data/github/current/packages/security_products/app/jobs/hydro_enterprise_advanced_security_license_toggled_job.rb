# typed: strict
# frozen_string_literal: true

class HydroEnterpriseAdvancedSecurityLicenseToggledJob < HydroMessageJob
  queue_as :hydro_security_products_enterprise_advanced_security_license_toggled

  retry_on_dirty_exit

  resolve_tenant_context do |message|
    ::Business.find_by(id: message.dig(:business_id))
  end

  sig { void }
  def perform
    business_id, request_id = message.values_at(
      :business_id,
      :request_id
    )
    business_id = T.let(business_id, Integer)
    business = Business.new(id: business_id)
    EnterpriseAdvancedSecurityLicenseToggledJob.perform_later(business_id: business_id, original_message: message)
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def failbot_log_context
    super.merge({
      app: "github-security-center"
    })
  end
end
