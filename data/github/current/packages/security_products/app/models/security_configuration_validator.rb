# typed: true
# frozen_string_literal: true

class SecurityConfigurationValidator < ActiveModel::Validator
  extend T::Sig

  RESERVED_NAMES = ["GitHub recommended", "None", "No"]

  sig { returns(String) }
  def self.ghas_features_unavailable_error_message
    readable_list_of_features = SecurityConfiguration::GHAS_FEATURES.map { _1.to_s.humanize }.join(", ")
    "#{readable_list_of_features} must be disabled when GitHub Advanced Security is disabled"
  end

  def validate(config)
    config_name = config.name&.strip
    if RESERVED_NAMES.include?(config_name) && config.target_type != "global"
      config.errors.add :name, "#{config_name} is a reserved configuration name"
    end

    # Dependency graph disabled and Dependabot alerts enabled or not_set
    # Dependency graph not_set and Dependabot alerts enabled
    if (config.dependency_graph_disabled? && !config.dependabot_alerts_disabled?) || (config.dependency_graph_not_set? && config.dependabot_alerts_enabled?)
      config.errors.add :dependabot_alerts, "Dependabot alerts must be disabled when Dependency graph is disabled"
    end

    if GitHub.dependency_graph_autosubmit_action_enabled?
      # Dependency graph disabled and Automatic dependency submission is enabled or not_set
      # Dependency graph not_set and Automatic dependency submission is enabled
      if (config.dependency_graph_disabled? && !config.dependency_graph_autosubmit_action_disabled?) ||
          (config.dependency_graph_not_set? && config.dependency_graph_autosubmit_action_enabled?)

        config.errors.add :dependency_graph_autosubmit_action,
                          "Automatic dependency submission must be disabled when Dependency graph is disabled"
      end
    end

    # Dependabot alerts disabled and Dependabot security updates enabled or not_set
    # Dependabot alerts not_set and Dependabot security updates enabled
    if (config.dependabot_alerts_disabled? && !config.dependabot_security_updates_disabled?) || (config.dependabot_alerts_not_set? && config.dependabot_security_updates_enabled?)
      config.errors.add :dependabot_security_updates, "Dependabot security updates must be disabled when Dependabot alerts are disabled"
    end

    # Secret scanning disabled and push protection enabled or not_set
    # Secret scanning not_set and push protection enabled
    if (config.secret_scanning_disabled? && !config.secret_scanning_push_protection_disabled?) || (config.secret_scanning_not_set? && config.secret_scanning_push_protection_enabled?)
      config.errors.add :secret_scanning_push_protection, "Push protection must be disabled when secret scanning is disabled"
    end

    # Secret scanning disabled and non provider patterns enabled or not_set
    # Secret scanning not_set and non provider patterns enabled
    if (config.secret_scanning_disabled? && !config.secret_scanning_non_provider_patterns_disabled?) || (config.secret_scanning_not_set? && config.secret_scanning_non_provider_patterns_enabled?)
      config.errors.add :secret_scanning_non_provider_patterns, "Non-provider patterns must be disabled when secret scanning is disabled"
    end

    # Secret scanning disabled and validity checks enabled or not_set
    # Secret scanning not_set and validity checks enabled
    if (config.secret_scanning_disabled? && !config.secret_scanning_validity_checks_disabled?) || (config.secret_scanning_not_set? && config.secret_scanning_validity_checks_enabled?)
      config.errors.add :secret_scanning_validity_checks, "Validity checks must be disabled when secret scanning is disabled"
    end

    if !config.enable_ghas && SecurityConfiguration::GHAS_FEATURES.any? { |feature| !config.send("#{feature}_disabled?") }
      config.errors.add :enable_ghas, self.class.ghas_features_unavailable_error_message
    end
  end
end
