# typed: strict
# frozen_string_literal: true

class BulkDisableService
  sig do
    params(
      entity: T.any(Organization, Business),
      actor: User,
      service: Symbol,
    ).void
  end
  def self.disable_service_on_private_repos(entity, actor, service)
    private_repos_to_disable_individually = []
    orgs = T.let([], T::Array[Organization])
    if entity.is_a?(Business)
      orgs.concat(entity.organizations.to_a)

      business_configs = SecurityConfiguration.where(target: entity).to_a
      business_configs.each do |config|
        # if the config has public repos (which we don't want to disable) and has our SKU enabled (meaning we need to take action), then we will detach and update the *private* repos indivually
        # leaving the public repos and config alone, because we want to leave the sku enabled on public repos
        if has_public_repos_and_needs_updating?(config, service)

          # if we can't update the config, disable the private repos individually
          private_repos_to_disable_individually.concat(get_private_repos(config))
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
        # if the config has public repos (which we don't want to disable) and has our SKU enabled (meaning we need to take action), then we will detach and update the *private* repos indivually
        # leaving the public repos and config alone, because we want to leave the sku enabled on public repos
        if has_public_repos_and_needs_updating?(config, service)

          # if we can't update the config, disable the private repos individually
          private_repos_to_disable_individually.concat(get_private_repos(config))
          next # skip to next config, don't update
        end

        disable_service_on_existing_config(config, :organization, actor, service)
      end

      # will need to individually disable any unattached private repos
      org.repositories.each do |repo|
        next if RepositorySecurityConfiguration.where(repository_id: repo.id).applied_or_attaching.any?
        next if repo.public?

        private_repos_to_disable_individually.push(repo)
      end
    end

    # disable the service on repos individually
    # this will detach repos as needed
    private_repos_to_disable_individually.each do |repo|
      next if repo.public?
      result = SecurityProduct::ServiceManager.new(repo).toggle_services(actor, services_to_disable: [[service, { "enablement_action": "trial_reset" }]])
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
    end
  end

  sig { params(config: SecurityConfiguration, service: Symbol).returns(T::Boolean) }
  def self.has_public_repos_and_needs_updating?(config, service)
    return false if get_service_state(config, service) == "disabled"
    any_public_repos(config)
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
end
