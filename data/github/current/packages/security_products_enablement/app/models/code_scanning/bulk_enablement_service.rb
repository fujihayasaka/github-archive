# typed: strict
# frozen_string_literal: true

module CodeScanning
  ##
  # Domain service for bulk enabling code scanning (default setup) through security configs.
  class BulkEnablementService
    CODE_ASSESSMENT_ENABLEMENT = "code_assessment_enablement"

    sig do
      params(
        entity: T.any(Organization, Business),
        actor: User,
        title: String,
        description: String,
      ).void
    end
    def initialize(entity:, actor:, title:, description:)
      @entity = T.let(entity, T.any(Organization, Business))
      @actor = T.let(actor, User)
      @title = T.let(title, String)
      @description = T.let(description, String)
      @bundled = T.let(entity.advanced_security_products_bundled?, T::Boolean)
    end

    sig do
      params(
        entity: T.any(Organization, Business),
        actor: User,
        title: String,
        description: String,
        enable_on_unattached_repos_with_conflict: T::Boolean,
      ).void
    end
    def self.enable_code_scanning_for_all_configs(entity, actor, title, description, enable_on_unattached_repos_with_conflict: false)
      new(entity:, actor:, title:, description:)
        .enable_code_scanning_for_all_configs(enable_on_unattached_repos_with_conflict:)
    end

    sig do
      params(
        entity: T.any(Organization, Business),
      ).returns(T::Boolean)
    end
    def self.entity_has_private_repo_conflict(entity)
      return false unless entity.advanced_security_purchased?

      # Fetch all relevant configs in a single query
      configs = if entity.is_a?(Business)
        SecurityConfiguration.where(target: entity)
          .or(SecurityConfiguration.where(target_type: "User", target_id: entity.organization_ids))
          .to_a
      else
        SecurityConfiguration.where(target: entity).to_a
      end

      # Filter to configs that will be modified (code scanning not fully enabled)
      config_ids = configs.filter_map do |config|
        next if config.code_scanning == "enabled" && config.code_scanning_options&.dig("allow_advanced") == true
        config.id
      end

      return false if config_ids.empty?

      # Batch-fetch all repo_id -> config_id mappings in one query
      repo_id_by_config = RepositorySecurityConfiguration
        .where(security_configuration_id: config_ids)
        .pluck(:security_configuration_id, :repository_id)

      return false if repo_id_by_config.empty?

      # Group repo IDs by config
      repos_by_config = repo_id_by_config.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }

      # Batch-fetch public status for all relevant repos in one query
      all_repo_ids = repos_by_config.values.flatten.uniq
      private_repo_ids = Repository.where(id: all_repo_ids, public: false).pluck(:id).to_set

      # Check if any single config has both public and private repos
      repos_by_config.each_value do |repo_ids|
        has_private = repo_ids.any? { |id| private_repo_ids.include?(id) }
        has_public = repo_ids.any? { |id| !private_repo_ids.include?(id) }
        return true if has_private && has_public
      end

      false
    end

    sig do
      params(
        org: Organization,
        actor: User,
        repo_ids: T::Array[Integer],
        title: String,
        description: String,
      ).void
    end
    def self.enable_code_scanning_for_repositories(org, actor, repo_ids, title, description)
      new(entity: org, actor:, title:, description:)
        .enable_code_scanning_for_repositories(repo_ids)
    end

    sig { params(enable_on_unattached_repos_with_conflict: T::Boolean).void }
    def enable_code_scanning_for_all_configs(enable_on_unattached_repos_with_conflict: false)
      return unless @entity.advanced_security_purchased?

      # update all configs for a business and its organizations
      org_configs = T.let([], T::Array[SecurityConfiguration])
      enterprise_configs_count = T.let(0, Integer)

      if @entity.is_a?(Business)
        enterprise_configs = SecurityConfiguration.where(target: @entity).to_a
        enterprise_configs_count = enterprise_configs.length

        enterprise_configs.each { |config| enable_code_scanning_on_existing_config(config) }

        @entity.organizations.each do |org|
          org_configs.concat(SecurityConfiguration.where(target: org).to_a)
        end
      else
        org_configs = SecurityConfiguration.where(target: @entity).to_a
      end

      GitHub.logger.info("Configurations collected for code scanning assessment enablement", base_log_context.merge(
        "gh.code_scanning.enterprise_configs_count" => enterprise_configs_count,
        "gh.code_scanning.organization_configs_count" => org_configs.length,
        "gh.code_scanning.enable_on_unattached_repos_with_conflict" => enable_on_unattached_repos_with_conflict,
      ))

      org_configs.each { |config| enable_code_scanning_on_existing_config(config) }

      create_and_apply_default_config(enable_on_unattached_repos_with_conflict:)
    end

    sig { params(repo_ids: T::Array[Integer]).void }
    def enable_code_scanning_for_repositories(repo_ids)
      org = T.cast(@entity, Organization)

      GitHub.logger.info("Enabling Code Scanning for selected repositories", base_log_context.merge(
        "gh.code_scanning.repository_ids" => repo_ids,
      ))

      repo_ids = org.repositories.where(id: repo_ids).distinct.pluck(:id)

      old_config_ids_by_repo_id = fetch_existing_config_mapping(repo_ids)
      attached_repo_ids = old_config_ids_by_repo_id.keys
      unattached_repo_ids = repo_ids - attached_repo_ids

      # Duplicate existing configs with code scanning enabled, then apply
      new_configs = duplicate_configs_with_code_scanning(org, old_config_ids_by_repo_id.values.uniq)

      attached_repo_ids
        .group_by { |repo_id| new_configs[old_config_ids_by_repo_id.fetch(repo_id)] }
        .each do |config, ids|
          next unless config
          apply_config_to_repositories(ids, config, context: "attached")
        end

      # Create a fresh config for repos that had no security configuration
      return if unattached_repo_ids.empty?

      new_config = create_code_scanning_configuration
      return unless new_config

      apply_config_to_repositories(unattached_repo_ids, new_config, context: "unattached")
    end

    private

    # --- Log context helpers ---

    sig { returns(T::Hash[String, T.untyped]) }
    def base_log_context
      {
        "gh.entity.id" => @entity.id,
        "gh.entity.type" => @entity.class.name,
        "gh.code_scanning.actor_id" => @actor.id,
      }
    end

    sig { params(config: SecurityConfiguration).returns(T::Hash[String, T.untyped]) }
    def config_log_context(config)
      base_log_context.merge(
        "gh.security_configuration.id" => config.id,
        "gh.security_configuration.name" => config.name,
        "gh.security_configuration.bundled" => config.bundled?,
      )
    end

    sig { params(repo_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
    def fetch_existing_config_mapping(repo_ids)
      result = T.let({}, T::Hash[Integer, Integer])
      RepositorySecurityConfiguration
        .where(repository_id: repo_ids)
        .in_batches do |batch|
          batch
            .pluck(:security_configuration_id, :repository_id)
            .each do |(old_config_id, repo_id)|
              result[repo_id] = old_config_id
            end
        end
      result
    end

    sig do
      params(
        org: Organization,
        old_config_ids: T::Array[Integer],
      ).returns(T::Hash[Integer, SecurityConfiguration])
    end
    def duplicate_configs_with_code_scanning(org, old_config_ids)
      result = T.let({}, T::Hash[Integer, SecurityConfiguration])

      SecurityConfiguration
        .where(id: old_config_ids)
        .find_each do |old_config|
          new_config = old_config.duplicate_and_enable_code_scanning(org)

          GitHub.logger.info("Security configuration duplication result", config_log_context(new_config || old_config).merge(
            "gh.security_configuration.created" => !!new_config,
          ))

          # If Code Scanning is already enabled on the old configuration,
          # the SecurityConfiguration#duplicate_and_enable_code_scanning
          # method will return nil. In this case, we want to reapply the
          # original configuration.
          result[old_config.id] = new_config || old_config
        end

      result
    end

    sig do
      params(
        repo_ids: T::Array[Integer],
        config: SecurityConfiguration,
        context: String,
      ).void
    end
    def apply_config_to_repositories(repo_ids, config, context:)
      Repository.where(id: repo_ids).find_each do |repo|
        result = config.apply_to_repository(repo, actor: @actor, override_existing_config: true)

        GitHub.logger.info("Applied security configuration to #{context} repository", config_log_context(config).merge(
          "gh.repository.id" => repo.id,
          "gh.security_configuration.applied" => result,
        ))
      end
    end

    sig { params(config: SecurityConfiguration).void }
    def enable_code_scanning_on_existing_config(config)
      update_model_hash = {
        "code_scanning" => "enabled",
        "code_scanning_options" => { "allow_advanced" => true },
      }

      if config.instance_of?(SecurityConfiguration)
        update_model_hash["enable_ghas"] = true
      else # UnbundledSecurityConfiguration
        update_model_hash["code_security_sku_enabled"] = true
      end

      # Note that this is updating the config in the same sense a user would —
      # everything meaningful that would happen if a user made this change will
      # happen here, including starting the jobs to apply the config to
      # attached repos.
      config.update_configuration(update_model_hash, @actor)

      if config.errors.any?
        report_config_error("Failed to update security configuration to enable code scanning", config)
      end
    end

    sig { params(visibility: Symbol).returns(T::Boolean) }
    def should_set_default_for?(visibility)
      default = SecurityConfigurationDefault.find_for(target: @entity, visibility: visibility).first
      return true unless default

      config = default.security_configuration
      config.blank? || config.code_scanning != "enabled"
    end

    sig { params(repo: Repository).void }
    def enable_code_scanning_individually(repo)
      auto_codeql = CodeScanning::AutoCodeql.new(repo)
      return if auto_codeql.enabled?

      result = SecurityProduct::ServiceManager.new(repo).toggle_services(@actor, services_to_enable: [[:auto_codeql, { "enablement_action": CODE_ASSESSMENT_ENABLEMENT }]])
      if result.error?
        Failbot.report(
          StandardError.new("Failed to enable code scanning default setup on repo #{repo.id}"),
          {
            error: result.error,
            repository_id: repo.id,
            business_id: @entity.is_a?(Business) ? @entity.id : nil,
            organization_id: @entity.is_a?(Organization) ? @entity.id : nil,
          }
        )
        GitHub.logger.error("Failed to enable code scanning default setup on repo", base_log_context.merge(
          "exception.type" => "CodeScanningEnablementError",
          "exception.message" => "Failed to enable code scanning default setup on repo",
          "gh.repository.id" => repo.id,
          "gh.code_scanning.error" => result.error,
        ))
      end
    end

    sig { params(repo: Repository).returns(T::Boolean) }
    def repo_has_secret_scanning_enabled?(repo)
      SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
    end

    sig { params(enable_on_unattached_repos_with_conflict: T::Boolean).void }
    def create_and_apply_default_config(enable_on_unattached_repos_with_conflict:)
      default_for_public = should_set_default_for?(:public)
      default_for_private = should_set_default_for?(:private)

      unconfigured_repo_ids = find_unconfigured_repo_ids

      GitHub.logger.info("Determined whether to create security configuration for code scanning", base_log_context.merge(
        "gh.code_scanning.repos_to_update_count" => unconfigured_repo_ids.length,
        "gh.code_scanning.default_for_public" => default_for_public,
        "gh.code_scanning.default_for_private" => default_for_private,
        "gh.code_scanning.create_new_config" => unconfigured_repo_ids.any? || default_for_private || default_for_public,
        "gh.code_scanning.bundled" => @bundled,
        "gh.security_configuration.name" => @title,
      ))

      # don't create a new config if there are no repos to update or defaults to set
      return unless unconfigured_repo_ids.any? || default_for_private || default_for_public

      new_config = create_code_scanning_configuration(
        default_for_public: default_for_public,
        default_for_private: default_for_private,
      )

      return unless new_config

      apply_default_config_to_repos(
        new_config,
        unconfigured_repo_ids,
        enable_on_unattached_repos_with_conflict: enable_on_unattached_repos_with_conflict,
      )
    end

    # Collect IDs of repos that don't yet have an applied/attaching security configuration.
    # Uses two separate queries (repos table + RSC table may be on different shards)
    # and filters in Ruby. Only collects IDs to keep memory usage low.
    sig { returns(T::Array[Integer]) }
    def find_unconfigured_repo_ids
      result = T.let([], T::Array[Integer])
      orgs = @entity.is_a?(Business) ? @entity.organizations : [@entity]

      orgs.each do |org|
        org_repo_ids = org.repositories.pluck(:id)
        next if org_repo_ids.empty?

        already_configured_repo_ids = RepositorySecurityConfiguration
          .where(repository_id: org_repo_ids)
          .applied_or_attaching
          .pluck(:repository_id)
          .to_set

        org_repo_ids.each { |id| result << id unless already_configured_repo_ids.include?(id) }
      end

      result
    end

    # Apply the given default config to repos, handling the secret-scanning conflict case.
    sig do
      params(
        new_config: SecurityConfiguration,
        repo_ids: T::Array[Integer],
        enable_on_unattached_repos_with_conflict: T::Boolean,
      ).void
    end
    def apply_default_config_to_repos(new_config, repo_ids, enable_on_unattached_repos_with_conflict:)
      Repository.where(id: repo_ids).find_each do |repo|
        # Do not apply the new config if this would disable secret scanning.
        # An unbundled code-security-only config does not carry
        # secret_protection_sku_enabled, so applying it would turn off
        # secret scanning on repos that already have it.
        if !new_config.enable_ghas && repo_has_secret_scanning_enabled?(repo)
          # Enable code scanning individually instead, without touching the
          # repo's existing security configuration.
          if enable_on_unattached_repos_with_conflict
            enable_code_scanning_individually(repo)
          end
          next
        end

        new_config.apply_to_repository(repo, actor: @actor, override_existing_config: true)
      end
    end

    sig do
      params(
        default_for_public: T::Boolean,
        default_for_private: T::Boolean,
      ).returns(T.nilable(SecurityConfiguration))
    end
    def create_code_scanning_configuration(default_for_public: false, default_for_private: false)
      security_products_manager = SecurityProductsEnablement::SecurityProductsManager.new
      model_hash = security_products_manager.model_hash

      model_hash["name"] = @title
      model_hash["description"] = @description

      # Only set code scanning to enabled if available
      available_services = security_products_manager.services

      unless available_services[:code_scanning]
        GitHub.logger.info("Code scanning is not available; skipping configuration creation", base_log_context)
        return nil
      end

      model_hash["code_scanning"] = "enabled"

      if @bundled
        model_hash["enable_ghas"] = true
      else
        model_hash["enable_ghas"] = false
        model_hash["code_security_sku_enabled"] = true
        model_hash["secret_protection_sku_enabled"] = false
        model_hash["secret_scanning"] = "disabled"
        model_hash["secret_scanning_push_protection"] = "disabled"
        model_hash["secret_scanning_non_provider_patterns"] = "disabled"
        model_hash["secret_scanning_delegated_bypass"] = "disabled"
        model_hash["secret_scanning_validity_checks"] = "disabled"
        model_hash["secret_scanning_generic_secrets"] = "disabled"
        model_hash["secret_scanning_delegated_alert_dismissal"] = "disabled"
        model_hash["secret_scanning_extended_metadata"] = "disabled"
      end

      # Enable default setup with advanced security allowed
      model_hash["code_scanning_options"] = { "allow_advanced" => true }

      GitHub.logger.info("Creating security configuration with model_hash", base_log_context.merge(
        "gh.security_configuration.name" => @title,
        "gh.security_configuration.bundled" => @bundled,
        "gh.security_configuration.model_hash" => model_hash,
        "gh.security_products.services" => available_services,
        "gh.security_configuration.default_for_new_public_repos" => default_for_public,
        "gh.security_configuration.default_for_new_private_repos" => default_for_private,
      ))

      config_class = @bundled ? SecurityConfiguration : UnbundledSecurityConfiguration
      new_config = config_class.create_configuration(
        target: @entity,
        model_hash: model_hash,
        default_for_new_public_repos: default_for_public,
        default_for_new_private_repos: default_for_private,
        enforcement: SecurityConfigurationPolicy::Enforcement::None,
        actor: @actor,
      )

      if new_config.persisted?
        log_config_creation_success(new_config)
        return new_config
      end

      GitHub.logger.info("Security configuration creation failed", base_log_context.merge(
        "gh.security_configuration.name" => @title,
        "gh.security_configuration.bundled" => @bundled,
        "gh.security_configuration.id" => new_config.id,
        "gh.security_configuration.errors" => new_config.errors.to_hash,
      ))

      return handle_name_collision(new_config) if name_taken?(new_config)

      report_config_error("Failed to create code scanning security configuration", new_config)
      nil
    end

    sig { params(config: SecurityConfiguration).void }
    def log_config_creation_success(config)
      GitHub.logger.info("Successfully created code scanning security configuration", config_log_context(config).merge(
        "gh.code_scanning.bundled" => @bundled,
      ))
    end

    sig { params(new_config: SecurityConfiguration).returns(T::Boolean) }
    def name_taken?(new_config)
      new_config.errors[:name].any? { |e| e.include?("taken") }
    end

    sig { params(new_config: SecurityConfiguration).returns(T.nilable(SecurityConfiguration)) }
    def handle_name_collision(new_config)
      new_config.name = "#{new_config.name} - #{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")}"
      new_config.save

      if new_config.errors.any?
        report_config_error("Failed to create code scanning security configuration after name collision", new_config)
        return nil
      end

      log_config_creation_success(new_config)
      new_config
    end

    sig { params(message: String, config: SecurityConfiguration).void }
    def report_config_error(message, config)
      Failbot.report(
        StandardError.new(message),
        {
          error: config.errors.to_hash,
          security_configuration_id: config.id,
          business_id: @entity.is_a?(Business) ? @entity.id : nil,
          organization_id: @entity.is_a?(Organization) ? @entity.id : nil,
        }
      )

      GitHub.logger.error(message, base_log_context.merge(
        "exception.type" => "SecurityConfigurationError",
        "exception.message" => message,
        "gh.code_scanning.config_errors" => config.errors.to_hash,
        "gh.security_configuration.id" => config.id,
      ))
    end
  end
end
