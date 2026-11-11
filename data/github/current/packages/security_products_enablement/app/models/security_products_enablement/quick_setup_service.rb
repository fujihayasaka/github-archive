# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  ##
  # Domain service for Quick Setup configuration management.
  # Handles creating, updating, and applying security configurations through the Quick Setup paradigm.
  #
  # Quick Setup uses simplified states (enabled/disabled/not_set/custom) that map to
  # SecurityConfiguration attributes. This service translates between these representations
  # and manages configuration drift detection.
  class QuickSetupService
    include GitHub::Memoizer

    sig { returns(Organization) }
    attr_reader :organization

    sig { returns(User) }
    attr_reader :actor

    sig { params(organization: Organization, actor: User).void }
    def initialize(organization:, actor:)
      @organization = organization
      @actor = actor
    end

    # Configuration metadata
    CONFIGURATION_DESCRIPTION_PREFIX = T.let("Created on ".freeze, String)

    # Feature groups for Quick Setup
    # Each group pairs core features (which determine Quick Setup state)
    # with companion features (which follow that state with individual defaults).
    SECRET_PROTECTION_GROUP = T.let(FeatureGroup.create(
      core_features: [
        :secret_scanning,
        :secret_scanning_push_protection,
        :secret_scanning_non_provider_patterns,
      ],
      companion_features: [
        CompanionFeature.new(name: :secret_scanning_validity_checks, recommended_when: -> { !GitHub.single_or_multi_tenant_enterprise? }),
        CompanionFeature.new(name: :secret_scanning_extended_metadata, recommended_when: -> { !GitHub.single_or_multi_tenant_enterprise? }),
        CompanionFeature.new(name: :secret_scanning_delegated_bypass),
        CompanionFeature.new(name: :secret_scanning_delegated_alert_dismissal, requires_core_enabled: true),
        CompanionFeature.new(name: :secret_scanning_generic_secrets, requires_core_enabled: true),
      ],
    ), FeatureGroup)

    CODE_SECURITY_GROUP = T.let(FeatureGroup.create(
      core_features: [
        :code_scanning,
      ],
      companion_features: [
        CompanionFeature.new(name: :code_scanning_delegated_alert_dismissal, requires_core_enabled: true),
      ],
    ), FeatureGroup)

    DEPENDABOT_GROUP = T.let(FeatureGroup.create(
      core_features: [
        :dependency_graph,
        :dependabot_alerts,
        :dependabot_security_updates,
      ],
      companion_features: [
        CompanionFeature.new(name: :dependency_graph_autosubmit_action),
        CompanionFeature.new(name: :dependabot_malware_alerts),
      ],
    ), FeatureGroup)

    # Dependabot companion features that also require the Code Security SKU.
    # These follow Dependabot state but must be disabled when Code Security is disabled.
    # Kept separate from DEPENDABOT_GROUP because their effective state depends on another group.
    DEPENDABOT_CODE_SECURITY_COMPANIONS = T.let([
      CompanionFeature.new(name: :dependabot_delegated_alert_dismissal, requires_core_enabled: true),
    ].freeze, T::Array[CompanionFeature])

    sig do
      params(
        secret_protection: T.nilable(State),
        code_security: T.nilable(State),
        dependabot: T.nilable(State),
        repositories: RepositorySelection,
        default_for_new_repositories: DefaultForNewRepositories,
        enforced: T::Boolean
      ).returns(SecurityConfiguration)
    end
    def create_and_apply_configuration(
      secret_protection:,
      code_security:,
      dependabot:,
      repositories:,
      default_for_new_repositories:,
      enforced: false
    )
      model_hash = security_products_manager.model_hash
      if bundled?
        model_hash["secret_protection_sku_enabled"] = false
        model_hash["code_security_sku_enabled"] = false
      else
        model_hash["enable_ghas"] = false
      end

      # Build model hash from Quick Setup states
      model_hash = build_model_hash_from_quick_setup_states(
        secret_protection:,
        code_security:,
        dependabot:,
        model_hash:
      )

      # Generate counter-based name and description
      model_hash["name"] = generate_configuration_name
      model_hash["description"] = generate_configuration_description

      klass = bundled? ? SecurityConfiguration : UnbundledSecurityConfiguration
      # Create the configuration
      config = klass.create_configuration(
        target: @organization,
        model_hash: model_hash,
        default_for_new_public_repos: default_for_new_repositories.public_or_all?,
        default_for_new_private_repos: default_for_new_repositories.private_or_all?,
        enforcement: enforced ? SecurityConfigurationPolicy::Enforcement::Enforced : SecurityConfigurationPolicy::Enforcement::None,
        actor: @actor
      )

      # If we hit a name collision due to a race condition, append a timestamp suffix and re-save
      if config.errors[:name].any?
        config.name = "#{config.name}-#{Time.current.strftime("%Y%m%d%H%M%S%6N")}"
        config.errors.clear
        config.save
      end

      # Only apply to repositories if configuration was created successfully (no validation errors)
      if config.errors.empty?
        if repositories.all? || repositories.selected?
          apply_configuration_to_repositories(configuration: config, repositories:)
        end
      end

      config
    end

    sig do
      params(
        configuration: SecurityConfiguration,
        repositories: RepositorySelection,
        default_for_new_repositories: DefaultForNewRepositories,
        secret_protection: T.nilable(State),
        code_security: T.nilable(State),
        dependabot: T.nilable(State),
        enforced: T::Boolean
      ).void
    end
    def update_configuration(
      configuration:,
      repositories:,
      default_for_new_repositories:,
      secret_protection: nil,
      code_security: nil,
      dependabot: nil,
      enforced: false
    )
      # For enterprise configs and GHR (global), only allow policy changes.
      # Service states (secret_protection, code_security, dependabot) are ignored
      # since these configurations can only be modified at their source level.
      if configuration.belongs_to_enterprise? || configuration.global?
        model_hash = {}
      else
        # Build model hash only for provided parameters
        model_hash = build_model_hash_from_quick_setup_states(
          secret_protection:,
          code_security:,
          dependabot:
        )
      end

      if repositories.not_applicable?
        repositories = nil
      end

      # Update the configuration and repository attachments
      configuration.update_configuration(
        model_hash,
        @actor,
        repositories:,
        policies_target: @organization,
        default_for_new_public_repos: default_for_new_repositories.public_or_all?,
        default_for_new_private_repos: default_for_new_repositories.private_or_all?,
        enforcement: enforced ? SecurityConfigurationPolicy::Enforcement::Enforced : SecurityConfigurationPolicy::Enforcement::None
      )
    end

    sig { params(configuration: SecurityConfiguration, repositories: RepositorySelection, override_existing: T::Boolean).void }
    def apply_configuration_to_repositories(configuration:, repositories:, override_existing: true)
      if repositories.all?
        SecurityProductsEnablement.domain.configurations.enqueue_bulk_attachment(
          security_configuration_id: configuration.id,
          organization: @organization,
          actor_id: @actor.id,
          action: :apply,
          repository_query: "visibility:public,private,internal",
          override_existing_config: override_existing,
        )
      elsif repositories.selected?
        SecurityProductsEnablement.domain.configurations.enqueue_bulk_attachment(
          security_configuration_id: configuration.id,
          organization: @organization,
          actor_id: @actor.id,
          action: :apply,
          repositories: repositories,
          repository_query: nil,
          override_existing_config: override_existing,
        )
      else
        raise ArgumentError, "Invalid repositories value for applying configuration"
      end
    end

    sig { params(configuration: SecurityConfiguration).returns(T::Hash[Symbol, State]) }
    def detect_configuration_drift(configuration)
      DriftDetector.new(organization:, configuration:).detect.to_hash
    end

    # Determines the repository selection state for a security configuration.
    #
    # Returns:
    #   - none: No repositories are attached to this configuration
    #   - all: All organization repositories are attached
    #   - selected(repo_ids): Some repositories are attached (includes the IDs)
    #   - not_applicable: Too many repositories to enumerate (exceeds max_repos)
    #
    # States counted as "attached": attached, enforced, attaching, updating
    # (i.e., applied states plus in-progress states)
    #
    # @param max_repos Maximum repositories to enumerate before returning not_applicable.
    #   This bounds query cost for large organizations. Default: 500
    sig { params(configuration: SecurityConfiguration, max_repos: Integer).returns(RepositorySelection) }
    def current_repository_selection(configuration, max_repos: RepositorySelection::MAX_REPOSITORY_IDS_FOR_QUICK_SETUP)
      # Get the IDs of repositories that are active (applied or in-progress states)
      # Uses index: index_repo_security_configs_on_org_security_config_repo (organization_id, security_configuration_id, repository_id)
      # Limit to max_repos + 1 to detect if we're over the limit
      attached_repo_ids = configuration.repository_security_configurations
        .active_for_quick_setup
        .where(organization_id: @organization.id)
        .limit(max_repos + 1)
        .pluck(:repository_id)

      return RepositorySelection.none if attached_repo_ids.empty?

      # If we have more than max_repos attached, return not_applicable
      # to signal the UI should use a different interface for large orgs
      return RepositorySelection.not_applicable if attached_repo_ids.size > max_repos

      # Check if all org repos are attached by looking for any repo not in our attached list
      # This is efficient: it short-circuits on the first unattached repo found
      any_unattached = @organization.repositories
        .where.not(id: attached_repo_ids)
        .limit(1)
        .exists?

      if any_unattached
        RepositorySelection.selected(attached_repo_ids)
      else
        RepositorySelection.all
      end
    end

    private

    sig { returns(String) }
    def generate_configuration_name
      prefix = "#{@organization.display_login}-org-config-"
      # Escape LIKE wildcards (%, _, \) in the prefix so they're matched literally, not as patterns
      escaped_prefix = ActiveRecord::Base.sanitize_sql_like(prefix)

      names = SecurityConfiguration
        .where(target: @organization)
        .where("name LIKE ?", "#{escaped_prefix}%")
        .pluck(:name)

      # This could be done in SQL, but since orgs generally have < 100 configs we are doing in ruby for readability
      existing_config_numbers = names.filter_map do |name|
        suffix = name.delete_prefix(prefix)
        suffix.match?(/\A\d+\z/) ? suffix.to_i : nil # matches strings that are only numbers
      end

      "#{prefix}#{(existing_config_numbers.max || 0) + 1}"
    end

    sig { returns(String) }
    def generate_configuration_description
      # Use the actor's preferred timezone for the date, falling back to UTC if not set
      date = Time.current.in_time_zone(@actor.time_zone).to_date
      "#{CONFIGURATION_DESCRIPTION_PREFIX}#{date.strftime("%B %-d, %Y")}"
    end

    sig do
      params(
        secret_protection: T.nilable(State),
        code_security: T.nilable(State),
        dependabot: T.nilable(State),
        model_hash: T.nilable(SecurityConfiguration::ModelHashType)
      ).returns(SecurityConfiguration::ModelHashType)
    end
    def build_model_hash_from_quick_setup_states(secret_protection:, code_security:, dependabot:, model_hash: nil)
      model_hash ||= T.let({}, SecurityConfiguration::ModelHashType)

      # Set bundled GHAS if available, otherwise use SKU-based approach
      if bundled?
        # So the logic here should match our GHAS validation logic where
        # unless all paid GHAS features are disabled, GHAS is considered enabled:
        #
        # Therefore if all provided paid states are disabled, we disable GHAS, otherwise we enable it
        # - Dependabot is excluded because it is a free feature that does not require GHAS
        # - This handles GHES, where a feature may not be installed and thus its state is nil
        # - This handles not set states which require GHAS as a repo that has this config applied may enable the paid feature
        #   - Note this only applies to the bundled SKU as the unbundled SKUs support the not_set state
        # - This handles custom states, since by definition custom means at least one feature is not disabled, otherwise it would be disabled
        has_all_disabled_paid_features = [secret_protection, code_security].compact.detect { |state| state != State::Disabled }.nil?
        model_hash["enable_ghas"] = !has_all_disabled_paid_features
      else
        # Enable SKUs based on what's being configured
        # Only set SKU values if the corresponding feature parameter is provided (not nil)
        # This allows partial updates without affecting unrelated SKUs
        if secret_protection && secret_protection != State::Custom
          model_hash["secret_protection_sku_enabled"] = secret_protection.to_security_config_tri_state
        end

        if code_security && code_security != State::Custom
          model_hash["code_security_sku_enabled"] = code_security.to_security_config_tri_state
        end
      end

      # On GHES, if this feature isn't installed we won't have a state value for it and we will take the default value
      # from the security products manager model hash
      apply_feature_group(model_hash, SECRET_PROTECTION_GROUP, secret_protection) if secret_protection && secret_protection != State::Custom
      apply_feature_group(model_hash, CODE_SECURITY_GROUP, code_security) if code_security && code_security != State::Custom

      if dependabot && dependabot != State::Custom
        apply_feature_group(model_hash, DEPENDABOT_GROUP, dependabot)
      end

      # DDAD companions require both Dependabot AND Code Security capability.
      # Force them disabled when code_security is explicitly disabled or unset,
      # even if dependabot is "custom" (i.e. its values are being preserved as-is).
      # Otherwise, a drifted DDAD=enabled value would fail SKU gate validation.
      code_security_unavailable = if bundled?
        [secret_protection, code_security].compact.all? { |s| s == State::Disabled }
      else
        code_security == State::Disabled || code_security == State::NotSet
      end

      if code_security_unavailable
        translate_companion_features(model_hash, DEPENDABOT_CODE_SECURITY_COMPANIONS, State::Disabled)
      elsif dependabot && dependabot != State::Custom
        translate_companion_features(model_hash, DEPENDABOT_CODE_SECURITY_COMPANIONS, dependabot)
      end

      model_hash
    end

    sig { params(model_hash: SecurityConfiguration::ModelHashType, group: FeatureGroup, state: State).void }
    def apply_feature_group(model_hash, group, state)
      group.core_features.each do |f|
        next unless service_enabled?(f)
        model_hash[f.to_s] = state.serialize
      end
      translate_companion_features(model_hash, group.companion_features, state)
    end

    sig do
      params(
        model_hash: SecurityConfiguration::ModelHashType,
        companions: T::Array[CompanionFeature],
        state: State
      ).void
    end
    def translate_companion_features(model_hash, companions, state)
      companions.each do |companion|
        next unless service_enabled?(companion.name)
        feature_state = companion.value_for_state(state).serialize
        model_hash[companion.name.to_s] = feature_state

        if companion.name == :dependency_graph_autosubmit_action && feature_state != "enabled"
          model_hash["dependency_graph_autosubmit_action_options"] = SecurityProduct::DependencyGraphAutosubmitAction::Options.default_attributes
        end
      end
    end

    sig { returns(T::Boolean) }
    def bundled?
      @organization.advanced_security_products_bundled?
    end

    sig { returns(SecurityProductsManager) }
    memoize def security_products_manager
      SecurityProductsManager.new
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    memoize def security_products_enablement_states
      security_products_manager.services
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def service_enabled?(feature)
      security_products_enablement_states[feature] == true
    end
  end
end
