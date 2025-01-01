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
end
