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

        disable_service_on_existing_config(config, :enterprise, actor, service)
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

        disable_service_on_existing_config(config, :organization, actor, service)
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

  sig { params(config: SecurityConfiguration, service: Symbol).returns(T::Hash[String, T.any(String, T::Boolean, T.untyped)]) }
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

        "target" => config.target
      }
      hash["secret_protection_sku_enabled"] = false unless config_is_bundled
    elsif service == :code_security
      hash = {
        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",
        "target" => config.target
      }
      hash["code_security_sku_enabled"] = false unless config_is_bundled
    elsif service == :advanced_security
      raise ArgumentError, "Advanced security only supported for bundled configurations" unless config_is_bundled
      hash = {
        "enable_ghas" => false,

        "code_scanning" => "disabled",
        "code_scanning_delegated_alert_dismissal" => "disabled",

        "secret_scanning" => "disabled",
        "secret_scanning_push_protection" => "disabled",
        "secret_scanning_delegated_bypass" => "disabled",
        "secret_scanning_delegated_alert_dismissal" => "disabled",
        "secret_scanning_validity_checks" => "disabled",
        "secret_scanning_non_provider_patterns" => "disabled",
        "secret_scanning_generic_secrets" => "disabled",
        "target" => config.target
      }
    else
      raise ArgumentError, "Invalid service: #{service}"
    end

    hash
  end

  sig { params(config: SecurityConfiguration, type: Symbol, actor: User, service: Symbol).void }
  def self.disable_service_on_existing_config(config, type, actor, service)
    # Note that this is updating the config in the same sense a user would
    # everything meaningful that would happen if a user made this change will happen here
    # including starting the jobs to apply the config to attached repos
    config.update_configuration(get_model_hash(config, service), actor, type: type)
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
    return Set.new unless FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, entity, default: false)

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

    # Exclude pre-trial enabled repos if the feature flag is enabled
    if FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, entity, default: false)
      pre_trial_repo_ids = get_pre_trial_enabled_repo_ids(entity, service.to_s, repo_ids)
      repo_ids = repo_ids - pre_trial_repo_ids.to_a
    end

    # Return only private repos that are safe to disable
    Repository.where(id: repo_ids, public: false).to_a
  end

  sig { params(config: SecurityConfiguration, service: Symbol, entity: T.any(Organization, Business)).returns(T::Boolean) }
  def self.has_pre_trial_enabled_repos?(config, service, entity)
    return false unless FeatureFlag.vexi.enabled?(:ghas_enable_trial_access_for_existing_users, entity, default: false)

    config_repo_ids = RepositorySecurityConfiguration.where(security_configuration_id: config.id).pluck(:repository_id)
    pre_trial_repo_ids = get_pre_trial_enabled_repo_ids(entity, service.to_s, config_repo_ids)
    pre_trial_repo_ids.any?
  end
end
