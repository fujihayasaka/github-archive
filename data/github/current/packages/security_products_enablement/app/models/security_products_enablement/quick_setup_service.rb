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
    # Core features that determine the Quick Setup state
    SECRET_PROTECTION_FEATURES = T.let([
      :secret_scanning,
      :secret_scanning_push_protection,
    ].freeze, T::Array[Symbol])

    CODE_SECURITY_FEATURES = T.let([
      :code_scanning,
    ].freeze, T::Array[Symbol])

    DEPENDABOT_FEATURES = T.let([
      :dependency_graph,
      :dependabot_alerts,
      :dependabot_security_updates,
    ].freeze, T::Array[Symbol])

    # Companion features that are set based on Quick Setup state but don't determine it
    # These are optional/advanced features that enhance the core functionality:
    # - delegated_bypass: Allows delegating secret scanning bypass authority
    # - delegated_alert_dismissal: Allows delegating alert dismissal authority
    # - autosubmit_action: Automatically submits dependency graph data
    # - validity_checks: Validates detected secrets against provider APIs
    # - non_provider_patterns: Scans for patterns not associated with known providers
    # - generic_secrets: Scans for generic passwords/secrets
    SECRET_PROTECTION_COMPANION_FEATURES = T.let([
      :secret_scanning_delegated_bypass,
      :secret_scanning_delegated_alert_dismissal,
      :secret_scanning_validity_checks,
      :secret_scanning_non_provider_patterns,
      :secret_scanning_extended_metadata,
      :secret_scanning_generic_secrets,
    ].freeze, T::Array[Symbol])

    CODE_SECURITY_COMPANION_FEATURES = T.let([
      :code_scanning_delegated_alert_dismissal,
    ].freeze, T::Array[Symbol])

    DEPENDABOT_COMPANION_FEATURES = T.let([
      :dependency_graph_autosubmit_action,
      :dependabot_malware_alerts,
    ].freeze, T::Array[Symbol])

    # Dependabot companion features that also require the Code Security SKU
    # These follow Dependabot state but must be disabled when Code Security is disabled
    DEPENDABOT_CODE_SECURITY_COMPANION_FEATURES = T.let([
      :dependabot_delegated_alert_dismissal,
    ].freeze, T::Array[Symbol])

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
        OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id: configuration.id,
          organization_id: @organization.id,
          actor_id: @actor.id,
          action: :apply,
          repository_query: "visibility:public,private,internal",
          override_existing_config: override_existing
        )
      elsif repositories.selected?
        OrganizationSecurityConfigurationJob.perform_later(
          security_configuration_id: configuration.id,
          organization_id: @organization.id,
          actor_id: @actor.id,
          action: :apply,
          repositories: repositories,
          repository_query: nil,
          override_existing_config: override_existing
        )
      else
        raise ArgumentError, "Invalid repositories value for applying configuration"
      end
    end

    sig { params(configuration: SecurityConfiguration).returns(T::Hash[Symbol, String]) }
    def detect_configuration_drift(configuration)
      # Cache services to avoid repeated SecurityProductsManager instantiation
      services = SecurityProductsManager.new.services
      # Gate dependabot_malware_alerts on the feature flag for the current org
      services[:dependabot_malware_alerts] = false unless dependabot_malware_frontend_enabled?

      # Extract and return the Quick Setup states for each feature group
      {
        secret_protection: determine_feature_group_state(configuration, SECRET_PROTECTION_FEATURES, SECRET_PROTECTION_COMPANION_FEATURES, services),
        code_security: determine_feature_group_state(configuration, CODE_SECURITY_FEATURES, CODE_SECURITY_COMPANION_FEATURES, services),
        dependabot: determine_feature_group_state(configuration, DEPENDABOT_FEATURES, DEPENDABOT_COMPANION_FEATURES + DEPENDABOT_CODE_SECURITY_COMPANION_FEATURES, services),
      }
    end

    sig { params(configuration: SecurityConfiguration, features: T::Array[Symbol], companion_features: T::Array[Symbol], services: T::Hash[Symbol, T::Boolean]).returns(String) }
    def determine_feature_group_state(configuration, features, companion_features, services)
      # Get all main feature states for this group
      main_states = features.filter_map do |feature|
        get_feature_value(configuration, feature)
      end

      # If we couldn't read any feature values, this is an error condition
      # This shouldn't happen with our predefined feature constants
      return "custom" if main_states.empty?

      if main_states.all? { |s| s == "disabled" }
        all_companions_disabled = companion_features.all? do |feature|
          get_feature_value(configuration, feature) == "disabled"
        end

        return all_companions_disabled ? "disabled" : "custom"
      end

      if main_states.all? { |s| s == "enabled" }
        # For enabled state, companion features must be at their default values or "more enabled"
        # Defaults when main feature is enabled:
        # - validity_checks and non_provider_patterns: "enabled"
        # - All other companions: "not_set"
        companions_acceptable = companion_features.all? do |feature|
          state = get_feature_value(configuration, feature)

          # Enterprise mode: unavailable features on GHES must be "disabled", which is acceptable
          next true if services[feature] != true && state == "disabled"

          if default_enabled_companion_feature?(feature)
            # Default is "enabled", only "enabled" is acceptable
            state == "enabled"
          else
            # Default is "not_set", "not_set" or "enabled" is acceptable
            state == "not_set" || state == "enabled"
          end
        end

        return companions_acceptable ? "enabled" : "custom"
      end

      if main_states.all? { |s| s == "not_set" }
        # For not_set state, companion features must be at their default values or "more enabled"
        # Defaults when main feature is not_set:
        # - alert dismissal features and generic_secrets: "disabled" (nothing can be less enabled)
        # - All other companions: "not_set"
        companions_acceptable = companion_features.all? do |feature|
          state = get_feature_value(configuration, feature)

          # Enterprise mode: unavailable features on GHES must be "disabled", which is acceptable
          next true if services[feature] != true && state == "disabled"

          # Features that default to "disabled" are always acceptable (can't be less enabled)
          # Others default to "not_set", so only "not_set" or "enabled" is acceptable
          default_disabled_companion_feature?(feature) || state == "not_set" || state == "enabled"
        end

        return companions_acceptable ? "not_set" : "custom"
      end

      # Main features are mixed - this is custom
      "custom"
    end

    sig { params(configuration: SecurityConfiguration, feature: Symbol).returns(T.nilable(String)) }
    def get_feature_value(configuration, feature)
      value = configuration[feature]
      # Convert enum to string if needed
      value.is_a?(String) ? value : value&.to_s
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def default_enabled_companion_feature?(feature)
      feature == :secret_scanning_validity_checks ||
        feature == :secret_scanning_non_provider_patterns ||
        feature == :secret_scanning_extended_metadata
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def default_disabled_companion_feature?(feature)
      feature == :secret_scanning_delegated_alert_dismissal ||
        feature == :code_scanning_delegated_alert_dismissal ||
        feature == :dependabot_delegated_alert_dismissal ||
        feature == :secret_scanning_generic_secrets
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
        # Therefore if all provided states are disabled, we disable GHAS, otherwise we enable it
        # - This handles GHES, where a feature may not be installed and thus its state is nil
        # - This handles not set states which require GHAS as a repo that has this config applied may enable the paid feature
        #   - Note this only applies to the bundled SKU as the unbundled SKUs support the not_set state
        # - This handles custom states, since by definition custom means at least one feature is not disabled, otherwise it would be disabled
        has_all_disabled_paid_features = [secret_protection, code_security, dependabot].compact.detect { |state| state != State::Disabled }.nil?
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
      if secret_protection && secret_protection != State::Custom
        # For custom state, we leave existing values as-is
        SECRET_PROTECTION_FEATURES.each { |f| model_hash[f.to_s] = secret_protection.serialize }
        translate_companion_features(model_hash, SECRET_PROTECTION_COMPANION_FEATURES, secret_protection)
      end

      if code_security && code_security != State::Custom
        CODE_SECURITY_FEATURES.each { |f| model_hash[f.to_s] = code_security.serialize }
        translate_companion_features(model_hash, CODE_SECURITY_COMPANION_FEATURES, code_security)
      end

      if dependabot && dependabot != State::Custom
        DEPENDABOT_FEATURES.each { |f| model_hash[f.to_s] = dependabot.serialize }
        translate_companion_features(model_hash, DEPENDABOT_COMPANION_FEATURES, dependabot)

        # When dependabot_allow_malware_frontend feature flag is disabled, force malware alerts to disabled
        # unless the dependabot state is not_set (in which case malware alerts should also be not_set)
        if !dependabot_malware_frontend_enabled? && dependabot != State::NotSet
          model_hash["dependabot_malware_alerts"] = "disabled"
        end

        # These features require both Dependabot AND Code Security SKU (unbundled only)
        # For bundled orgs, they just follow Dependabot state
        # For unbundled orgs, disabled if either dependabot or code_security is disabled
        effective_state = dependabot
        effective_state = State::Disabled if !bundled? && code_security == State::Disabled
        translate_companion_features(model_hash, DEPENDABOT_CODE_SECURITY_COMPANION_FEATURES, effective_state)
      end

      model_hash
    end

    sig { params(model_hash: SecurityConfiguration::ModelHashType, features: T::Array[Symbol], state: State).void }
    def translate_companion_features(model_hash, features, state)
      # Companion features follow specific rules based on Quick Setup state
      features.each do |feature|
        feature_key = feature.to_s

        next unless service_enabled?(feature)
        model_hash[feature_key] = companion_feature_value(feature, state)
      end
    end

    sig { params(feature: Symbol, state: State).returns(String) }
    def companion_feature_value(feature, state)
      case state
      when State::Enabled
        # When enabled:
        # - Validity checks and non-provider patterns are enabled
        # - All other companions are not_set (user can configure them separately)
        default_enabled_companion_feature?(feature) ? "enabled" : "not_set"
      when State::Disabled
        "disabled"
      when State::NotSet
        # When not_set:
        # - Alert dismissal features and generic secrets are disabled
        # - All other companions are not_set
        default_disabled_companion_feature?(feature) ? "disabled" : "not_set"
      when State::Custom
        raise ArgumentError, "Cannot determine companion feature value for custom state"
      else
        T.absurd(state)
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

    sig { returns(T::Boolean) }
    memoize def dependabot_malware_frontend_enabled?
      FeatureFlag.vexi.enabled?("dependabot_allow_malware_frontend", @organization, @actor, default: false)
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def service_enabled?(feature)
      security_products_enablement_states[feature] == true
    end
  end
end
