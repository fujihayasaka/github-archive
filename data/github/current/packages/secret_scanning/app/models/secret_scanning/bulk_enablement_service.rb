# typed: strict
# frozen_string_literal: true

module SecretScanning
  ##
  # Domain service for bulk enabling secret scanning through security configs.
  class BulkEnablementService
    TRIAL_ENABLEMENT = "trial_enablement"
    SECRET_ASSESSMENT_ENABLEMENT = "secret_assessment_enablement"

    sig { params(entity: T.any(Organization, Business), actor: User, title: String, description: String).void }
    def self.unbundle_and_enable_all_secret_scanning(entity, actor, title, description)
      return unless entity.secret_protection_purchased_for_entity?

      # update all configs for a (business and its) organizations
      org_configs = []

      if entity.is_a?(Business)
        enterprise_configs = SecurityConfiguration.where(target: entity).to_a

        enterprise_configs.each do |config|
          unbundle_and_enable_secret_scanning_on_existing_config(config, :enterprise, actor)
        end

        orgs = entity.organizations
        orgs.each do |org|
          org_configs.concat(SecurityConfiguration.where(target: org).to_a)
        end
      else
        org_configs = SecurityConfiguration.where(target: entity).to_a
      end

      GitHub.logger.info("Configurations collected for unbundling and enablement", {
        "gh.entity.id" => entity.id,
        "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization",
        "gh.secret_scanning.enterprise_configs_count" => entity.is_a?(Business) ? enterprise_configs&.length || 0 : 0,
        "gh.secret_scanning.organization_configs_count" => org_configs.length,
        "gh.secret_scanning.actor_id" => actor.id
      })

      org_configs.each do |config|
        unbundle_and_enable_secret_scanning_on_existing_config(config, :organization, actor)
      end

      create_and_apply_default_config(entity, actor, title, description, TRIAL_ENABLEMENT, bundled: false, include_private_repos: true, enable_on_unattached_repos_with_conflict: false) # always unbundled, include private repos, don't enable on unattached repos with conflict
    end

    sig do
      params(
        entity: T.any(Organization, Business),
        actor: User,
        title: String,
        description: String,
        include_private_repos: T::Boolean,
        enable_on_unattached_repos_with_conflict: T::Boolean
      ).void
    end
    def self.enable_all_secret_scanning(entity, actor, title, description, include_private_repos: true, enable_on_unattached_repos_with_conflict: false)
      return unless entity.advanced_security_purchased?

      # update all configs for a (business and its) organizations
      org_configs = []
      public_repos_to_enable_individually = []

      if entity.is_a?(Business)
        enterprise_configs = SecurityConfiguration.where(target: entity).to_a

        enterprise_configs.each do |config|
          if !include_private_repos && has_private_repos_and_needs_updated?(config)
            public_repos_to_enable_individually.concat(get_public_repos(config))
            next # skip to next config, don't update
          end

          enable_secret_scanning_on_existing_config(config, :enterprise, actor)
        end

        orgs = entity.organizations
        orgs.each do |org|
          org_configs.concat(SecurityConfiguration.where(target: org).to_a)
        end
      else
        org_configs = SecurityConfiguration.where(target: entity).to_a
      end

      GitHub.logger.info("Configurations collected for assessment enablement", {
        "gh.entity.id" => entity.id,
        "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization",
        "gh.secret_scanning.enterprise_configs_count" => entity.is_a?(Business) ? enterprise_configs&.length || 0 : 0,
        "gh.secret_scanning.organization_configs_count" => org_configs.length,
        "gh.secret_scanning.public_repos_to_enable_individually_count" => public_repos_to_enable_individually.length,
        "gh.secret_scanning.include_private_repos" => include_private_repos,
        "gh.secret_scanning.enable_on_unattached_repos_with_conflict" => enable_on_unattached_repos_with_conflict,
        "gh.secret_scanning.actor_id" => actor.id
      })

      org_configs.each do |config|
        if !include_private_repos && has_private_repos_and_needs_updated?(config)
          public_repos_to_enable_individually.concat(get_public_repos(config))
          next # skip to next config, don't update
        end

        enable_secret_scanning_on_existing_config(config, :organization, actor)
      end

      create_and_apply_default_config(
        entity,
        actor,
        title,
        description,
        SECRET_ASSESSMENT_ENABLEMENT,
        bundled: entity.advanced_security_products_bundled?,
        include_private_repos: include_private_repos,
        enable_on_unattached_repos_with_conflict: enable_on_unattached_repos_with_conflict,
        public_repos_to_enable_individually: public_repos_to_enable_individually
      )
    end

    sig do
      params(
        entity: T.any(Organization, Business)
      ).returns(T::Boolean)
    end
    def self.entity_has_private_repo_conflict(entity)
      return false unless entity.advanced_security_purchased?

      configs = []

      if entity.is_a?(Business)
        configs = SecurityConfiguration.where(target: entity).to_a

        orgs = entity.organizations
        orgs.each do |org|
          configs.concat(SecurityConfiguration.where(target: org).to_a)
        end
      else
        configs = SecurityConfiguration.where(target: entity).to_a
      end

      configs.each do |config|
        if has_private_repo_conflict?(config)
          return true
        end
      end

      false
    end

    sig do
      params(
        entity: T.any(Organization, Business),
        actor: User,
        title: String,
        description: String,
        enablement_action: String,
        bundled: T::Boolean,
        include_private_repos: T::Boolean,
        enable_on_unattached_repos_with_conflict: T::Boolean,
        public_repos_to_enable_individually: T::Array[Repository]
      ).void
    end
    def self.create_and_apply_default_config(entity, actor, title, description, enablement_action, bundled:, include_private_repos:, enable_on_unattached_repos_with_conflict:, public_repos_to_enable_individually: [])
      # Create default config for any remaining repos
      new_config_as_default_for_public = true
      new_config_as_default_for_private = true

      if SecurityConfigurationDefault.find_for(target: entity, visibility: :public).any?
        existing_default_config = SecurityConfigurationDefault.find_for(target: entity, visibility: :public).first
        existing_config = existing_default_config&.security_configuration
        if existing_config.present? && existing_config.secret_scanning == "enabled" && existing_config.secret_scanning_push_protection == "enabled"
          new_config_as_default_for_public = false
        end
      end
      if SecurityConfigurationDefault.find_for(target: entity, visibility: :private).any?
        existing_default_config = SecurityConfigurationDefault.find_for(target: entity, visibility: :private).first
        existing_config = existing_default_config&.security_configuration
        if existing_config.present? && existing_config.secret_scanning == "enabled" && existing_config.secret_scanning_push_protection == "enabled"
          new_config_as_default_for_private = false
        end
      end
      if !include_private_repos
        new_config_as_default_for_private = false
      end

      # Apply new config to existing repos without a config
      repos_to_update = public_repos_to_enable_individually
      if entity.is_a?(Business)
        orgs = entity.organizations
      else
        orgs = [entity]
      end
      orgs.each do |org|
        org.repositories.each do |repo|
          next if RepositorySecurityConfiguration.where(repository_id: repo.id).applied_or_attaching.any?
          next if !include_private_repos && !repo.public?

          repos_to_update.push(repo)
        end
      end

      GitHub.logger.info("Determined whether to create security configuration for secret scanning", {
        "gh.entity.id" => entity.id,
        "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization",
        "gh.secret_scanning.repos_to_update_count" => repos_to_update.length,
        "gh.secret_scanning.default_for_public" => new_config_as_default_for_public,
        "gh.secret_scanning.default_for_private" => new_config_as_default_for_private,
        "gh.secret_scanning.create_new_config" => repos_to_update.any? || new_config_as_default_for_private || new_config_as_default_for_public,
        "gh.secret_scanning.enablement_action" => enablement_action,
        "gh.secret_scanning.bundled" => bundled,
        "gh.security_configuration.name" => title,
      })

      # don't create a new config if there are no repos to update or defaults to set
      return unless repos_to_update.any? || new_config_as_default_for_private || new_config_as_default_for_public

      # Start with the base model_hash from SecurityProductsManager
      security_products_manager = SecurityProductsEnablement::SecurityProductsManager.new
      model_hash = security_products_manager.model_hash

      # Override with specific values for this use case
      model_hash["name"] = title
      model_hash["description"] = description
      model_hash["target"] = entity

      # Only set secret scanning to enabled if available
      available_services = security_products_manager.services
      model_hash["secret_scanning"] = "enabled" if available_services[:secret_scanning]
      model_hash["secret_scanning_push_protection"] = "enabled" if available_services[:secret_scanning_push_protection]

      GitHub.logger.info("Creating security configuration with model_hash", {
        "gh.entity.id" => entity.id,
        "gh.entity.type" => entity.class,
        "gh.security_configuration.name" => title,
        "gh.security_configuration.bundled" => bundled,
        "gh.security_configuration.model_hash" => model_hash,
        "gh.security_products.services" => available_services,
        "gh.security_configuration.default_for_new_public_repos" => new_config_as_default_for_public,
        "gh.security_configuration.default_for_new_private_repos" => new_config_as_default_for_private
      })

      if bundled
        model_hash["enable_ghas"] = true
        new_config = SecurityConfiguration.create_configuration(
          model_hash: model_hash,
          default_for_new_public_repos: new_config_as_default_for_public,
          default_for_new_private_repos: new_config_as_default_for_private,
          enforcement: SecurityConfigurationPolicy::Enforcement::None,
          actor: actor,
        )
      else
        model_hash["enable_ghas"] = false
        model_hash["secret_protection_sku_enabled"] = true
        model_hash["code_security_sku_enabled"] = false
        model_hash["code_scanning"] = "disabled"
        new_config = UnbundledSecurityConfiguration.create_configuration(
          model_hash: model_hash,
          default_for_new_public_repos: new_config_as_default_for_public,
          default_for_new_private_repos: new_config_as_default_for_private,
          enforcement: SecurityConfigurationPolicy::Enforcement::None,
          actor: actor,
        )
      end

      GitHub.logger.info("Security configuration creation result", {
        "gh.entity.id" => entity.id,
        "gh.security_configuration.name" => title,
        "gh.security_configuration.bundled" => bundled,
        "gh.security_configuration.created" => new_config.persisted?,
        "gh.security_configuration.id" => new_config.id,
        "gh.security_configuration.errors" => new_config.errors.any? ? new_config.errors.to_hash : nil
      })

      if new_config.errors.any?
        # if config already exists with this name, add a timestamp to the name
        if new_config.errors[:name].any? { |e| e.include?("taken") }
          new_config.name = "#{new_config.name} - #{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")}"
          new_config.save
          if new_config.errors.any?
            Failbot.report(
              SecretScanning::Errors::Error.new("Failed to create security configuration after name collision"),
              {
                error: new_config.errors.to_hash,
                business_id: entity.is_a?(Business) ? entity.id : nil,
                organization_id: entity.is_a?(Organization) ? entity.id : nil,
              }
            )
            GitHub.logger.error("Failed to create security configuration after name collision", {
              "exception.type" => "SecurityConfigurationError",
              "exception.message" => "Failed to create security configuration after name collision",
              "gh.secret_scanning.config_errors" => new_config.errors.to_hash,
              "gh.entity.id" => entity.id,
              "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization"
            })
            return
          end
        else
          Failbot.report(
            SecretScanning::Errors::Error.new("Failed to create security configuration"),
            {
              error: new_config.errors.to_hash,
              business_id: entity.is_a?(Business) ? entity.id : nil,
              organization_id: entity.is_a?(Organization) ? entity.id : nil,
            }
          )
          GitHub.logger.error("Failed to create security configuration", {
            "exception.type" => "SecurityConfigurationError",
            "exception.message" => "Failed to create security configuration",
            "gh.secret_scanning.config_errors" => new_config.errors.to_hash,
            "gh.entity.id" => entity.id,
            "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization"
          })
          return
        end
      end

      GitHub.logger.info("Successfully created security configuration", {
        "gh.entity.id" => entity.id,
        "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization",
        "gh.security_configuration.id" => new_config.id,
        "gh.security_configuration.name" => new_config.name,
        "gh.secret_scanning.bundled" => bundled,
        "gh.secret_scanning.repos_to_apply_count" => repos_to_update.length
      })

      repos_to_update.each do |repo|
        # do not apply the new config if this would disable code scanning
        if repo.turboscan_considers_code_scanning_enabled? && !new_config.enable_ghas
          # enable secret scanning individually instead if we're supposed to
          # this will be used for secret assessment only as of 2025
          if enable_on_unattached_repos_with_conflict
            token_scanning_feature = SecretScanning::Features::Repo::TokenScanning.new(repo)
            unless token_scanning_feature.enabled?
              if repo.feature_enabled?(:token_scanning_bulk_enablement_force_enable)
                result = SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [[:token_scanning, { "enablement_action": enablement_action }]])
                if result.error?
                  Failbot.report(
                    SecretScanning::Errors::Error.new("Failed to enable token scanning on repo #{repo.id}"),
                    {
                      error: result.error,
                      repository_id: repo.id,
                      business_id: entity.is_a?(Business) ? entity.id : nil,
                      organization_id: entity.is_a?(Organization) ? entity.id : nil,
                    }
                  )
                  GitHub.logger.error("Failed to enable token scanning on repo", {
                    "exception.type" => "TokenScanningEnablementError",
                    "exception.message" => "Failed to enable token scanning on repo",
                    "gh.repository.id" => repo.id,
                    "gh.secret_scanning.error" => result.error,
                    "gh.entity.id" => entity.id,
                    "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization"
                  })
                end
              else
                SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [:token_scanning])
              end
            end

            push_protection_feature = SecretScanning::Features::Repo::PushProtection.new(repo)
            unless push_protection_feature.enabled?
              if repo.feature_enabled?(:token_scanning_bulk_enablement_force_enable)
                result = SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [[:token_scanning_push_protection, { "enablement_action": enablement_action }]])
                if result.error?
                  Failbot.report(
                    SecretScanning::Errors::Error.new("Failed to enable push protection on repo #{repo.id}"),
                    {
                      error: result.error,
                      repository_id: repo.id,
                      business_id: entity.is_a?(Business) ? entity.id : nil,
                      organization_id: entity.is_a?(Organization) ? entity.id : nil,
                    }
                  )
                  GitHub.logger.error("Failed to enable push protection on repo", {
                    "exception.type" => "PushProtectionEnablementError",
                    "exception.message" => "Failed to enable push protection on repo",
                    "gh.repository.id" => repo.id,
                    "gh.secret_scanning.error" => result.error,
                    "gh.entity.id" => entity.id,
                    "gh.entity.type" => entity.is_a?(Business) ? "Business" : "Organization"
                  })
                end
              else
                SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_enable: [:token_scanning_push_protection])
              end
            end
          end
          next # skip applying the new config
        end

        new_config.apply_to_repository(repo, actor: actor, override_existing_config: true)
      end
    end

    sig { params(config: SecurityConfiguration).returns(T::Boolean) }
    def self.has_private_repo_conflict?(config)
      # there is no conflict if the config doesn't need any changes
      return false if config.secret_scanning == "enabled" && config.secret_scanning_push_protection == "enabled"

      # configs have a conflict if they have both private and public repos
      any_private_repos(config) && any_public_repos(config)
    end

    sig { params(config: SecurityConfiguration).returns(T::Boolean) }
    def self.has_private_repos_and_needs_updated?(config)
      return false if config.secret_scanning == "enabled" && config.secret_scanning_push_protection == "enabled"

      any_private_repos(config)
    end

    sig { params(config: SecurityConfiguration).returns(T::Boolean) }
    def self.any_private_repos(config)
      repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
      Repository.where(id: repo_ids, public: false).any?
    end

    sig { params(config: SecurityConfiguration).returns(T::Boolean) }
    def self.any_public_repos(config)
      repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
      Repository.where(id: repo_ids, public: true).any?
    end

    sig { params(config: SecurityConfiguration).returns(T::Array[Repository]) }
    def self.get_public_repos(config)
      repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
      Repository.where(id: repo_ids, public: true).to_a
    end

    sig { params(config: SecurityConfiguration, type: Symbol, actor: User).void }
    def self.enable_secret_scanning_on_existing_config(config, type, actor)
      if config.instance_of?(SecurityConfiguration)
        update_model_hash = {
          "enable_ghas" => true,
          "secret_scanning" => "enabled",
          "secret_scanning_push_protection" => "enabled",
          "target" => config.target
        }
      else # It's an instance of UnbundledSecurityConfiguration
        update_model_hash = {
          "secret_protection_sku_enabled" => true,
          "secret_scanning" => "enabled",
          "secret_scanning_push_protection" => "enabled",
          "target" => config.target
        }
      end

      # Note that this is updating the config in the same sense a user would
      # everything meaningful that would happen if a user made this change will happen here
      # including starting the jobs to apply the config to attached repos
      config.update_configuration(update_model_hash, actor, type: type)

      if config.errors.any?
        Failbot.report(
          SecretScanning::Errors::Error.new("Failed to update security configuration to enable secret scanning"),
          {
            error: config.errors.to_hash,
            security_configuration_id: config.id,
          }
        )
        GitHub.logger.error("Failed to update security configuration", {
          "exception.type" => "SecurityConfigurationUpdateError",
          "exception.message" => "Failed to update security configuration to enable secret scanning",
          "gh.secret_scanning.config_errors" => config.errors.to_hash,
          "gh.security_configuration.id" => config.id,
          "gh.secret_scanning.update_model_hash" => update_model_hash,
          "gh.secret_scanning.entity_type" => type.to_s
        })
      end
    end

    sig { params(config: SecurityConfiguration, type: Symbol, actor: User).void }
    def self.unbundle_and_enable_secret_scanning_on_existing_config(config, type, actor)
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

      # Note that this is updating the config in the same sense a user would
      # everything meaningful that would happen if a user made this change will happen here
      # including starting the jobs to apply the config to attached repos
      unbundled_config.update_configuration(update_model_hash, actor, type: type)

      if unbundled_config.errors.any?
        Failbot.report(
          SecretScanning::Errors::Error.new("Failed to update security configuration to enable secret scanning"),
          {
            error: unbundled_config.errors.to_hash,
            security_configuration_id: unbundled_config.id,
          }
        )
        GitHub.logger.error("Failed to update security configuration", {
          "exception.type" => "SecurityConfigurationUpdateError",
          "exception.message" => "Failed to update unbundled security configuration to enable secret scanning",
          "gh.secret_scanning.config_errors" => unbundled_config.errors.to_hash,
          "gh.security_configuration.id" => unbundled_config.id,
          "gh.secret_scanning.update_model_hash" => update_model_hash,
          "gh.secret_scanning.entity_type" => type.to_s
        })
      end
    end
  end
end
