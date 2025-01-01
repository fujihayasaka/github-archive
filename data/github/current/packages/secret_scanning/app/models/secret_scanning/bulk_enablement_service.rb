# typed: strict
# frozen_string_literal: true

module SecretScanning
  ##
  # Domain service for bulk enabling secret scanning through security configs.
  class BulkEnablementService

    sig { params(business: Business, actor: User).void }
    def self.enable_all_secret_scanning(business, actor)
      return unless business.admins.any? && SecretScanning::Features::FeatureFlagHelper.feature_flag_enabled?(business.admins.first, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS_AUTO_ENABLE)
      return unless business.secret_protection_purchased_for_entity?

      # Get all configs for business and its organizations
      enterprise_configs = SecurityConfiguration.where(target: business).to_a

      org_configs = []
      orgs = business.organizations
      orgs.each do |org|
        org_configs.concat(SecurityConfiguration.where(target: org).to_a)
      end

      # Update existing configurations

      enterprise_configs.each do |config|
        unbundle_and_enable_secret_scanning(config, :enterprise, actor)
      end

      org_configs.each do |config|
        unbundle_and_enable_secret_scanning(config, :organization, actor)
      end

      # Create default config for any remaining repos
      new_config_as_default_for_public = true
      new_config_as_default_for_private = true
      if SecurityConfigurationDefault.find_for(target: business, visibility: :public).any?
        new_config_as_default_for_public = false
      end
      if SecurityConfigurationDefault.find_for(target: business, visibility: :private).any?
        new_config_as_default_for_private = false
      end

      new_config = UnbundledSecurityConfiguration.create_configuration(
        model_hash: {
          "name" => "Secret Protection Enabled",
          "description" => "Try Secret Protection as part of your enterprise trial.",
          "enable_ghas" => false,
          "code_security_sku_enabled" => true,
          "secret_protection_sku_enabled" => true,
          "private_vulnerability_reporting" => "not_set",
          "dependency_graph" => "not_set",
          "dependency_graph_autosubmit_action" => "not_set",
          "dependency_graph_autosubmit_action_options" => {},
          "dependabot_alerts" => "not_set",
          "dependabot_security_updates" => "not_set",
          "code_scanning" => "not_set",
          "secret_scanning" => "enabled",
          "secret_scanning_push_protection" => "enabled",
          "secret_scanning_delegated_bypass" => "not_set",
          "secret_scanning_validity_checks" => "not_set",
          "secret_scanning_non_provider_patterns" => "not_set",
          "target" => business
        },
        default_for_new_public_repos: new_config_as_default_for_public,
        default_for_new_private_repos: new_config_as_default_for_private,
        enforcement: :not_enforced,
        actor: actor,
      )
      if new_config.errors.any?
        Rails.logger.error("Failed to create security configuration: #{new_config.errors.to_hash}")
        return
      end

      # Apply new config to existing repos without a config
      orgs.each do |org|
        org.repositories.each do |repo|
          next if repo.repository_security_configuration.present?

          new_config.apply_to_repository(
            actor,
            repo,
            actor,
            override_existing_config: false
          )
        end
      end
    end

    sig { params(config: SecurityConfiguration, type: Symbol, actor: User).void }
    def self.unbundle_and_enable_secret_scanning(config, type, actor)
      update_model_hash = {
        "secret_protection_sku_enabled" => true,
        "secret_scanning" => "enabled",
        "secret_scanning_push_protection" => "enabled",
        "target" => config.target
      }
      if config.instance_of?(SecurityConfiguration)
        unbundled_config = config.unbundle!
      else # It's an instance of UnbundledSecurityConfiguration
        unbundled_config = config
      end
      unbundled_config.update_configuration(update_model_hash, actor, type: type)

      if unbundled_config.errors.any?
        Failbot.report("Failed to update security configuration to enable secret scanning", {
          "error" => unbundled_config.errors.to_hash,
          "security_configuration_id" => unbundled_config.id,
        })
        Rails.logger.error("Failed to update security configuration: #{unbundled_config.errors.to_hash}")
      end
    end
  end
end
