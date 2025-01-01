# typed: true
# frozen_string_literal: true

class UnbundledSecurityConfiguration < SecurityConfiguration

  CODE_SECURITY_SKU_FEATURES = %i[
    code_scanning
  ].freeze

  SECRET_PROTECTION_SKU_FEATURES = %i[
    secret_scanning
    secret_scanning_non_provider_patterns
    secret_scanning_push_protection
    secret_scanning_delegated_bypass
    secret_scanning_validity_checks
  ].freeze

  validates_with UnbundledSecurityConfigurationValidator

  sig { returns(SecurityConfiguration) }
  def bundle!
    raise ArgumentError, "Cannot bundle global configurations" if global?

    bundled = T.cast(becomes!(SecurityConfiguration), SecurityConfiguration)

    if code_security_sku_enabled || secret_protection_sku_enabled
      bundled.enable_ghas = true
    end

    bundled.code_security_sku_enabled = false
    bundled.secret_protection_sku_enabled = false
    bundled.save!

    bundled
  end

  sig { override.returns(T::Boolean) }
  def bundled?
    false
  end

  # See BundledSecurityConfiguration#attributes_for_duplication_and_secret_scanning_enablement
  # for behavior when the security configuration belongs to an organization on bundled GHAS.
  sig { override.params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_secret_scanning_enablement(target: self.target, name: self.name)
    {
      target:,
      name:,
      enable_ghas: false,
      code_security_sku_enabled:, # Unbundled only
      code_scanning:,
      code_scanning_delegated_alert_dismissal:,
      code_scanning_options:,
      dependabot_alerts:,
      dependabot_security_updates:,
      dependency_graph:,
      dependency_graph_autosubmit_action:,
      dependency_graph_autosubmit_action_options:,
      private_vulnerability_reporting:,
      secret_protection_sku_enabled: true, # Unbundled only
      secret_scanning: "enabled",
      secret_scanning_delegated_alert_dismissal:,
      secret_scanning_delegated_bypass:,
      secret_scanning_generic_secrets:,
      secret_scanning_non_provider_patterns:,
      secret_scanning_push_protection: "enabled",
      secret_scanning_validity_checks:,
    }
  end
end
