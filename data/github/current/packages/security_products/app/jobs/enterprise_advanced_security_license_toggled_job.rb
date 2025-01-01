# typed: strict
# frozen_string_literal: true

class EnterpriseAdvancedSecurityLicenseToggledJob < AbstractEnterpriseChangeFanoutJob
  extend T::Sig

  queue_as :security_products_enterprise_advanced_security_license_toggled

  retry_on_dirty_exit

  sig { params(organization_id: Integer).void }
  def process_organization(organization_id)
    GlobalInstrumenter.instrument("security_products.organization_advanced_security_license_toggled", {
      organization_id: organization_id,
      original_message: arguments.dig(0, :original_message),
    })
  end

  protected

  sig { returns(T.untyped) }
  def logging_context
    super.merge({
      "gh.security_products.job.source_event": "enterprise_advanced_security_license_toggled",
    })
  end

  sig { returns(T.untyped) }
  def failbot_context
    super.merge({
      "gh.security_products.job.source_event": "enterprise_advanced_security_license_toggled",
    })
  end
end
