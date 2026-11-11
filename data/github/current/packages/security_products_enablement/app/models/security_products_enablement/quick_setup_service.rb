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
    # Valid Quick Setup states
    VALID_STATES = T.let(%w[enabled disabled not_set custom].freeze, T::Array[String])

    # Configuration metadata
    CONFIGURATION_DESCRIPTION = T.let("Created via Quick Setup".freeze, String)

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
    SECRET_PROTECTION_COMPANION_FEATURES = T.let([
      :secret_scanning_delegated_bypass,
      :secret_scanning_delegated_alert_dismissal,
    ].freeze, T::Array[Symbol])

    CODE_SECURITY_COMPANION_FEATURES = T.let([
      :code_scanning_delegated_alert_dismissal,
    ].freeze, T::Array[Symbol])

    DEPENDABOT_COMPANION_FEATURES = T.let([
      :dependency_graph_autosubmit_action,
    ].freeze, T::Array[Symbol])

    sig do
      params(
        organization: Organization,
        actor: User,
        secret_protection: T.nilable(String),
        code_security: T.nilable(String),
        dependabot: T.nilable(String),
        repository_ids: T.nilable(T.any(Symbol, T::Array[Integer])),
        enforced: T::Boolean
      ).returns(T.nilable(SecurityConfiguration))
        .checked(:always)
        .on_failure(:raise)
    end
    def self.create_and_apply_configuration(
      organization:,
      actor:,
      secret_protection: nil,
      code_security: nil,
      dependabot: nil,
      repository_ids: nil,
      enforced: false
    )
      # Build model hash from Quick Setup states
      model_hash = build_model_hash_from_quick_setup_states(
        organization: organization,
        secret_protection: secret_protection,
        code_security: code_security,
        dependabot: dependabot
      )

      # Generate timestamped name and description
      model_hash["name"] = "quick-setup-configuration-#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
      model_hash["description"] = CONFIGURATION_DESCRIPTION

      # Create the configuration
      config = SecurityConfiguration.create_configuration(
        model_hash: model_hash,
        default_for_new_public_repos: true,
        default_for_new_private_repos: true,
        enforcement: enforced ? SecurityConfigurationPolicy::Enforcement::Enforced : SecurityConfigurationPolicy::Enforcement::None,
        actor: actor
      )

      # Return nil if config creation failed completely
      return nil if config.nil?

      # Only apply to repositories if configuration was created successfully (no validation errors)
      if config.errors.empty?
        # Apply to repositories based on repository_ids value:
        # - :all - Apply to all repositories in the organization (uses query)
        # - [1, 2, 3] - Apply to specific repository IDs
        # - [] or nil - Don't apply to any repositories
        if repository_ids == :all
          apply_configuration_to_all_repositories(
            configuration: config,
            organization: organization,
            actor: actor
          )
        elsif repository_ids.is_a?(Array) && repository_ids.any?
          apply_configuration_to_repositories(
            configuration: config,
            organization: organization,
            actor: actor,
            repository_ids: repository_ids
          )
        end
      end

      config
    end

    sig do
      params(
        configuration: SecurityConfiguration,
        organization: Organization,
        actor: User,
        repository_ids: T::Array[Integer],
        override_existing: T::Boolean
      ).void
    end
    def self.apply_configuration_to_repositories(
      configuration:,
      organization:,
      actor:,
      repository_ids:,
      override_existing: false
    )
      OrganizationSecurityConfigurationJob.perform_later(
        security_configuration_id: configuration.id,
        organization_id: organization.id,
        actor_id: actor.id,
        action: :apply,
        repository_ids: repository_ids,
        repository_query: nil,
        override_existing_config: override_existing
      )
    end

    sig do
      params(
        configuration: SecurityConfiguration,
        organization: Organization,
        actor: User,
        override_existing: T::Boolean
      ).void
    end
    def self.apply_configuration_to_all_repositories(
      configuration:,
      organization:,
      actor:,
      override_existing: false
    )
      OrganizationSecurityConfigurationJob.perform_later(
        security_configuration_id: configuration.id,
        organization_id: organization.id,
        actor_id: actor.id,
        action: :apply,
        repository_ids: [],
        repository_query: "visibility:public,private,internal",
        override_existing_config: override_existing
      )
    end

    sig do
      params(
        configuration: SecurityConfiguration,
        features: T::Array[Symbol]
      ).returns(String)
    end
    def self.determine_feature_group_state(configuration, features)
      # Get all feature states for this group by explicitly reading each feature
      states = features.filter_map do |feature|
        value = case feature
        when :secret_scanning
          configuration.secret_scanning
        when :secret_scanning_push_protection
          configuration.secret_scanning_push_protection
        when :code_scanning
          configuration.code_scanning
        when :dependency_graph
          configuration.dependency_graph
        when :dependabot_alerts
          configuration.dependabot_alerts
        when :dependabot_security_updates
          configuration.dependabot_security_updates
        else
          next
        end
        # Convert enum to string if needed
        value.is_a?(String) ? value : value&.to_s
      end

      # If we couldn't read any feature values, this is an error condition
      # This shouldn't happen with our predefined feature constants
      return "custom" if states.empty?

      # Check if all features WITHIN THIS GROUP are in the same state
      # Each feature group (secret_protection, code_security, dependabot) is evaluated independently
      # For a group to match a Quick Setup preset, all features in that group must have the same state
      unique_states = states.uniq

      if unique_states.length == 1
        # All features in this group are in the same state - matches a Quick Setup preset
        unique_states.first
      else
        # Mixed states within this group means it has been customized beyond Quick Setup presets
        "custom"
      end
    end

    sig do
      params(
        organization: Organization,
        secret_protection: T.nilable(String),
        code_security: T.nilable(String),
        dependabot: T.nilable(String)
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build_model_hash_from_quick_setup_states(
      organization:,
      secret_protection: nil,
      code_security: nil,
      dependabot: nil
    )
      security_products_manager = SecurityProductsEnablement::SecurityProductsManager.new
      model_hash = security_products_manager.model_hash

      model_hash["target"] = organization

      # Set bundled GHAS if available, otherwise use SKU-based approach
      if organization.advanced_security_products_bundled?
        model_hash["enable_ghas"] = true
      else
        model_hash["enable_ghas"] = false
        # Enable SKUs based on what's being configured
        model_hash["secret_protection_sku_enabled"] = secret_protection == "enabled"
        model_hash["code_security_sku_enabled"] = code_security == "enabled"
      end

      # Translate Secret Protection state
      if secret_protection.present?
        translate_state_to_features(
          model_hash,
          SECRET_PROTECTION_FEATURES,
          secret_protection
        )
        translate_companion_features(
          model_hash,
          SECRET_PROTECTION_COMPANION_FEATURES,
          secret_protection
        )
      end

      # Translate Code Security state
      if code_security.present?
        translate_state_to_features(
          model_hash,
          CODE_SECURITY_FEATURES,
          code_security
        )
        translate_companion_features(
          model_hash,
          CODE_SECURITY_COMPANION_FEATURES,
          code_security
        )
      end

      # Translate Dependabot state
      if dependabot.present?
        translate_state_to_features(
          model_hash,
          DEPENDABOT_FEATURES,
          dependabot
        )
        translate_companion_features(
          model_hash,
          DEPENDABOT_COMPANION_FEATURES,
          dependabot
        )
      end

      model_hash
    end

    sig do
      params(
        model_hash: T::Hash[String, T.untyped],
        features: T::Array[Symbol],
        state: String
      ).void
    end
    def self.translate_state_to_features(model_hash, features, state)
      unless VALID_STATES.include?(state)
        raise ArgumentError, "Invalid state '#{state}'. Must be one of: #{VALID_STATES.join(', ')}"
      end

      feature_value = case state
      when "enabled"
        "enabled"
      when "disabled"
        "disabled"
      when "not_set"
        "not_set"
      when "custom"
        # For custom state, we leave existing values as-is
        return
      end

      features.each do |feature|
        model_hash[feature.to_s] = feature_value
      end
    end

    sig do
      params(
        model_hash: T::Hash[String, T.untyped],
        features: T::Array[Symbol],
        state: String
      ).void
    end
    def self.translate_companion_features(model_hash, features, state)
      # Companion features follow specific rules based on Quick Setup state
      features.each do |feature|
        feature_key = feature.to_s

        # If the feature is already set to "disabled" in the model_hash (meaning it's not available),
        # don't override it. This respects product availability from SecurityProductsManager.
        next if model_hash[feature_key] == "disabled"

        model_hash[feature_key] = companion_feature_value(feature, state)
      end
    end

    sig do
      params(
        configuration_id: Integer
      ).returns(T::Hash[Symbol, String])
    end
    def self.detect_configuration_drift(configuration_id:)
      # Fetch the configuration
      config = SecurityConfiguration.find_by(id: configuration_id)
      return { error: "Configuration not found" } if config.nil?

      # Extract and return the Quick Setup states for each feature group
      {
        secret_protection: determine_feature_group_state(config, SECRET_PROTECTION_FEATURES),
        code_security: determine_feature_group_state(config, CODE_SECURITY_FEATURES),
        dependabot: determine_feature_group_state(config, DEPENDABOT_FEATURES),
      }
    end

    sig do
      params(
        feature: Symbol,
        state: String
      ).returns(String)
    end
    def self.companion_feature_value(feature, state)
      case state
      when "enabled"
        # When enabled, all companions are not_set (user can configure them separately)
        "not_set"
      when "disabled"
        # When disabled, all companions are disabled except secret_scanning_delegated_bypass stays not_set
        feature == :secret_scanning_delegated_bypass ? "not_set" : "disabled"
      when "not_set"
        # When not_set:
        # - Alert dismissal features are disabled
        # - All other companions are not_set
        alert_dismissal_feature?(feature) ? "disabled" : "not_set"
      else
        "not_set"
      end
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def self.alert_dismissal_feature?(feature)
      feature == :secret_scanning_delegated_alert_dismissal ||
        feature == :code_scanning_delegated_alert_dismissal
    end
  end
end
