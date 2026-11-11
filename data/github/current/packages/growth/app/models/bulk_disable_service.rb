# typed: strict
# frozen_string_literal: true

class BulkDisableService
  BATCH_SIZE = 100

  sig do
    params(
      entity: T.any(Organization, Business),
      actor: User,
      service: Symbol,
      enablement_action: String,
    ).void
  end
  def self.disable_service_on_private_repos(entity, actor, service, enablement_action: "trial_reset")
    private_repos_to_disable_individually = []
    orgs = T.let([], T::Array[Organization])
    if entity.is_a?(Business)
      orgs.concat(entity.organizations.to_a)

      business_configs = SecurityConfiguration.where(target: entity).to_a
      business_configs.each do |config|
        # Check if we should skip updating this config due to public repos or pre-trial enabled repos
        if should_skip_config_update?(config, service, entity)
          # Disable only the repos that are safe to disable individually
          private_repos_to_disable_individually.concat(get_safe_to_disable_private_repos(config, entity, service))
          next # skip to next config, don't update
        end

        disable_service_on_existing_config(config, actor, service)
      end
    else
      orgs = [entity]
    end

    orgs.each do |org|
      org_configs = SecurityConfiguration.where(target: org).to_a
      org_configs.each do |config|
        # Check if we should skip updating this config due to public repos or pre-trial enabled repos
        # Use the original entity (the one that started the trial) when checking pre-trial records
        # so that Business-level pre-trial entries are considered for org configs under that business.
        if should_skip_config_update?(config, service, entity)
          # Disable only the repos that are safe to disable individually
          private_repos_to_disable_individually.concat(get_safe_to_disable_private_repos(config, entity, service))
          next # skip to next config, don't update
        end

        disable_service_on_existing_config(config, actor, service)
      end

      org.repositories.in_batches(of: BATCH_SIZE) do |repos_batch|
        repo_ids = repos_batch.pluck(:id)
        pre_trial_enabled_repo_ids = get_pre_trial_enabled_repo_ids(entity, service.name, repo_ids)

        # will need to individually disable any unattached private repos
        repos_batch.each do |repo|
          if SecretScanning::Features::FeatureFlagHelper::feature_flag_enabled_in_hierarchy?(repo, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::DISABLE_RECOMMENDED_CONFIG)
            next if RepositorySecurityConfiguration.where(repository_id: repo.id).where.not(security_configuration_id: SecurityConfiguration.github_recommended_configuration&.id).applied_or_attaching.any?
          else
            next if RepositorySecurityConfiguration.where(repository_id: repo.id).applied_or_attaching.any?
          end
          next if pre_trial_enabled_repo_ids.include?(repo.id)
          next if repo.public?

          private_repos_to_disable_individually.push(repo)
        end
      end
    end

    # disable the service on repos individually
    # this will detach repos as needed
    private_repos_to_disable_individually.each do |repo|
      next if repo.public?

      # Only attempt to disable secret scanning if it's currently enabled
      if service == :token_scanning
        next unless SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
      end

      result = SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_disable: [[service, { "enablement_action": enablement_action }]])
      if result.error?
        Failbot.report(
          SecretScanning::Errors::Error.new("Failed to disable token scanning on repo #{repo.id}"),
          {
            error: result.error,
            repository_id: repo.id,
            business_id: entity.is_a?(Business) ? entity.id : nil,
            organization_id: entity.is_a?(Organization) ? entity.id : nil,
          }
        )
        Rails.logger.error("Failed to disable token scanning on repo #{repo.id}: #{result.error}")
      end
    end

    update_default_configs_for_trial_end(entity, service)
  end

  sig { params(config: SecurityConfiguration, service: Symbol).returns(String) }
  def self.get_service_state(config, service)
    if service == :token_scanning
      config.secret_scanning
    elsif service == :code_security
      config.code_scanning
    elsif service == :advanced_security
      return "enabled" if config.enable_ghas
      "disabled"
    end
  end

  sig { params(config: SecurityConfiguration).returns(T::Boolean) }
  def self.any_public_repos(config)
    repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
    Repository.where(id: repo_ids, public: true).any?
  end

  sig { params(config: SecurityConfiguration).returns(T::Array[Repository]) }
  def self.get_private_repos(config)
    repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
    Repository.where(id: repo_ids, public: false).to_a
  end

  sig { params(config: SecurityConfiguration, service: Symbol).returns(SecurityConfiguration::ModelHashType) }
  def self.get_model_hash(config, service)
    config_is_bundled = config.instance_of?(SecurityConfiguration)
    if service == :token_scanning
      hash = {
        "secret_protection_sku_enabled" => false,
        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
      }
      hash["secret_protection_sku_enabled"] = false unless config_is_bundled
    elsif service == :code_security
      hash = {
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "dependabot_delegated_alert_dismissal" => "disabled",
      }
      hash["code_security_sku_enabled"] = false unless config_is_bundled
    elsif service == :advanced_security
      raise ArgumentError, "Advanced security only supported for bundled configurations" unless config_is_bundled
      hash = {
        "enable_ghas" => false,

        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "dependabot_delegated_alert_dismissal" => "disabled",

        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
      }
    else
      raise ArgumentError, "Invalid service: #{service}"
    end

    hash
  end

  sig { params(config: SecurityConfiguration, actor: User, service: Symbol).void }
  def self.disable_service_on_existing_config(config, actor, service)
    # Note that this is updating the config in the same sense a user would
    # everything meaningful that would happen if a user made this change will happen here
    # including starting the jobs to apply the config to attached repos
    config.update_configuration(get_model_hash(config, service), actor)
    if config.errors.any?
      Failbot.report(
        SecretScanning::Errors::Error.new("Failed to update security configuration to disable #{service}"),
        {
          error: config.errors.to_hash,
          security_configuration_id: config.id,
        }
      )
      Rails.logger.error("Failed to update security configuration: #{config.errors.to_hash}")
    end
  end

  sig { params(entity: T.any(Organization, Business), sku_name: String, repository_ids: T.nilable(T::Array[Integer])).returns(T::Set[Integer]) }
  def self.get_pre_trial_enabled_repo_ids(entity, sku_name, repository_ids = nil)

    # Map service names to SKU names used in the database
    # Only token_scanning maps to a different SKU name (secret_protection)
    database_sku_name = sku_name == "token_scanning" ? "secret_protection" : sku_name

    repo_ids = Set.new

    # Query pre-trial rows for the entity itself
    query = SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.where(
      target_id: entity.id,
      target_type: entity.class.name,
      sku_name: database_sku_name
    )
    query = query.where(repository_id: repository_ids) if repository_ids
    query.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      repo_ids.merge(batch.map(&:repository_id))
    end

    repo_ids
  end

  sig { params(config: SecurityConfiguration, service: Symbol, entity: T.any(Organization, Business)).returns(T::Boolean) }
  def self.should_skip_config_update?(config, service, entity)
    return false if get_service_state(config, service) == "disabled"

    # Skip if config has public repos (we don't want to disable services on public repos)
    return true if any_public_repos(config)

    # Skip if config has pre-trial enabled repos and the feature flag is enabled
    return true if has_pre_trial_enabled_repos?(config, service, entity)

    false
  end

  sig { params(config: SecurityConfiguration, entity: T.any(Organization, Business), service: Symbol).returns(T::Array[Repository]) }
  def self.get_safe_to_disable_private_repos(config, entity, service)
    repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)

    # Exclude pre-trial enabled repos
    pre_trial_repo_ids = get_pre_trial_enabled_repo_ids(entity, service.to_s, repo_ids)
    repo_ids = repo_ids - pre_trial_repo_ids.to_a

    # Return only private repos that are safe to disable
    Repository.where(id: repo_ids, public: false).to_a
  end

  sig { params(config: SecurityConfiguration, service: Symbol, entity: T.any(Organization, Business)).returns(T::Boolean) }
  def self.has_pre_trial_enabled_repos?(config, service, entity)

    config_repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
    pre_trial_repo_ids = get_pre_trial_enabled_repo_ids(entity, service.to_s, config_repo_ids)
    pre_trial_repo_ids.any?
  end

  sig { params(entity: T.any(Organization, Business), service: Symbol).void }
  def self.update_default_configs_for_trial_end(entity, service)
    scope = SecurityConfigurationDefault.includes(:security_configuration).where(default_for_new_private_repos: true)
    pre_trial_configs_lookup = build_pre_trial_configs_lookup(entity, service.name)

    # Check the entity's own default config
    default_config = scope.where(target: entity).first
    remove_default_config_if_billable(entity, service, default_config, pre_trial_configs_lookup) if default_config

    if entity.is_a?(Business)
      # Cache organizations for efficient lookup
      organizations_by_id = entity.organizations.index_by(&:id)

      org_defaults = scope.where(target_type: "User", target_id: organizations_by_id.keys)

      org_defaults.each do |org_default|
        remove_default_config_if_billable(entity, service, org_default, pre_trial_configs_lookup)
      end
    end
  end

  sig { params(entity: T.any(Organization, Business), service: String).returns(T::Hash[T::Array[T.any(Integer, String)], T::Boolean]) }
  def self.build_pre_trial_configs_lookup(entity, service)
    database_sku_name = service == "token_scanning" ? "secret_protection" : service
    pre_trial_configs = T.unsafe(SecurityProductsEnablement::PreGhasTrialDefaultPrivateRepoSecurityConfiguration)
      .for_billable_entity_and_sku(entity, database_sku_name)

    # Create lookup hash: [target_id, target_type, security_configuration_id] => true
    pre_trial_configs.each_with_object({}) do |config, hash|
      key = [config.target_id, config.target_type, config.security_configuration_id]
      hash[key] = true
    end
  end

  sig { params(entity: T.any(Organization, Business), service: Symbol, default_config: SecurityConfigurationDefault, pre_trial_configs_lookup: T::Hash[T::Array[T.any(Integer, String)], T::Boolean]).void }
  def self.remove_default_config_if_billable(entity, service, default_config, pre_trial_configs_lookup)
    config = default_config.security_configuration
    return unless config.present?

    # Check if the specific service is enabled
    return unless get_service_state(config, service) == "enabled"

    # Check pre-trial table using the lookup hash for efficiency
    # If config was enabled for SKU pre-trial skip updating
    lookup_key = [default_config.target_id, default_config.target_type, config.id]
    return if pre_trial_configs_lookup[lookup_key]

    # Update to set default_for_private_repos as false
    default_config.update(default_for_new_private_repos: false)

    if default_config.errors.any?
      Failbot.report(
        SecretScanning::Errors::Error.new("Failed to update security configuration default for trial end"),
        {
          error: default_config.errors.to_hash,
          security_configuration_id: config.id,
          target_id: default_config.target_id,
          target_type: default_config.target_type,
          service: service.to_s,
        }
      )
      Rails.logger.error("Failed to update security configuration default #{default_config.id}: #{default_config.errors.to_hash}")
    end
  end
end
