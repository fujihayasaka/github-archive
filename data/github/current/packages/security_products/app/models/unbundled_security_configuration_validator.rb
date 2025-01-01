# typed: true
# frozen_string_literal: true

class UnbundledSecurityConfigurationValidator < ActiveModel::Validator

  sig { returns(String) }
  def self.code_security_unavailable_error_message
    readable_list_of_features = UnbundledSecurityConfiguration::CODE_SECURITY_SKU_FEATURES.map { _1.to_s.humanize }.join(", ")
    "#{readable_list_of_features} must be disabled when Code Security is disabled"
  end

  sig { returns(String) }
  def self.secret_protection_unavailable_error_message
    readable_list_of_features = UnbundledSecurityConfiguration::SECRET_PROTECTION_SKU_FEATURES.map { _1.to_s.humanize }.join(", ")
    "#{readable_list_of_features} must be disabled when Secret Protection is disabled"
  end

  def validate(config)
    if config.enable_ghas
      config.errors.add :enable_ghas, "This entity is not eligible to use the bundled GitHub Advanced Security product. Use `code_security_sku_enabled` and `secret_protection_sku_enabled` instead."
    end

    if config.target_type != "global" && config.target&.feature_enabled?(:code_scanning_security_configuration_ternary_state)
      if config.code_security_sku_enabled == false && UnbundledSecurityConfiguration::CODE_SECURITY_SKU_FEATURES.any? { |feature| !config.send("#{feature}_disabled?") }
        config.errors.add :code_security_sku_enabled, self.class.code_security_unavailable_error_message
      end

      if config.secret_protection_sku_enabled == false && UnbundledSecurityConfiguration::SECRET_PROTECTION_SKU_FEATURES.any? { |feature| !config.feature_nil_or_disabled?(feature) }
        config.errors.add :secret_protection_sku_enabled, self.class.secret_protection_unavailable_error_message
      end
    else
      if !config.code_security_sku_enabled && UnbundledSecurityConfiguration::CODE_SECURITY_SKU_FEATURES.any? { |feature| !config.send("#{feature}_disabled?") }
        config.errors.add :code_security_sku_enabled, self.class.code_security_unavailable_error_message
      end

      if !config.secret_protection_sku_enabled && UnbundledSecurityConfiguration::SECRET_PROTECTION_SKU_FEATURES.any? { |feature| !config.feature_nil_or_disabled?(feature) }
        config.errors.add :secret_protection_sku_enabled, self.class.secret_protection_unavailable_error_message
      end
    end
  end
end
