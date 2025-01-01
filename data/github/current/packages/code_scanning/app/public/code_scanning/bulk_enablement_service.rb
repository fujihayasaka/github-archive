# typed: strict
# frozen_string_literal: true

module CodeScanning
  class BulkEnablementService

    # Unbundle and enable code scanning on an existing security configuration
    # This follows the same pattern as SecretScanning::BulkEnablementService.unbundle_and_enable_secret_scanning_on_existing_config
    sig { params(config: SecurityConfiguration, type: Symbol, actor: User).void }
    def self.unbundle_and_enable_code_scanning_on_existing_config(config, type, actor)
      update_model_hash = {
        "code_security_sku_enabled" => true,
        "code_scanning" => "enabled",
        "target" => config.target
      }

      if config.instance_of?(SecurityConfiguration)
        unbundled_config = config.unbundle!
      else # It's an instance of UnbundledSecurityConfiguration
        unbundled_config = config
      end

      # Update the configuration following the same pattern as secret scanning
      unbundled_config.update_configuration(update_model_hash, actor, type: type)

      if unbundled_config.errors.any?
        Failbot.report(
          StandardError.new("Failed to update security configuration to enable code scanning"),
          {
            error: unbundled_config.errors.to_hash,
            security_configuration_id: unbundled_config.id,
          }
        )
        GitHub.logger.error("Failed to update security configuration", {
          "exception.type" => "SecurityConfigurationUpdateError",
          "exception.message" => "Failed to update unbundled security configuration to enable code scanning",
          "gh.code_scanning.config_errors" => unbundled_config.errors.to_hash,
          "gh.security_configuration.id" => unbundled_config.id,
        })
      end
    end
  end
end
