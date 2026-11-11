# typed: strict
# frozen_string_literal: true

# Encapsulates configuration duplication logic used by risk-assessment workflows
# to create derived configs with specific security features (e.g. Code Security,
# Secret Protection) enabled.
# Note: UnbundledSecurityConfiguration overrides the `attributes_for_duplication_*`
# methods — Ruby method dispatch ensures those overrides still take precedence.
module SecurityConfiguration::FeatureEnablementDuplication
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SecurityConfiguration }

  sig { params(target: Organization).returns(T.nilable(SecurityConfiguration)) }
  def duplicate_and_enable_secret_scanning(target)
    # This configuration already has Secret Protection enabled!
    return nil if secret_scanning_enabled? && secret_scanning_push_protection_enabled?

    duplicate_and_enable_feature(
      target:,
      name_suffix: "with Secret Protection",
      existing_scope: T.cast(self.class, T.class_of(SecurityConfiguration)).secret_scanning_enabled,
      build_target_attributes: ->(t, n) { attributes_for_duplication_and_secret_scanning_enablement(target: t, name: n) },
      compare_attributes: ->(config) { config.attributes_for_duplication_and_secret_scanning_enablement },
    )
  end

  # See UnbundledSecurityConfiguration#attributes_for_duplication_and_secret_scanning_enablement
  # for behavior when the security configuration belongs to an organization on unbundled GHAS.
  sig { overridable.params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_secret_scanning_enablement(target: self.target, name: self.name)
    {
      target:,
      name:,
      enable_ghas: true,
      code_scanning:,
      code_scanning_delegated_alert_dismissal:,
      code_scanning_options:,
      dependabot_alerts:,
      dependabot_security_updates:,
      dependabot_malware_alerts:,
      dependency_graph:,
      dependency_graph_autosubmit_action:,
      dependency_graph_autosubmit_action_options:,
      private_vulnerability_reporting:,
      secret_scanning: "enabled",
      secret_scanning_delegated_alert_dismissal:,
      secret_scanning_delegated_bypass:,
      secret_scanning_generic_secrets:,
      secret_scanning_non_provider_patterns:,
      secret_scanning_push_protection: "enabled",
      secret_scanning_validity_checks:,
    }
  end

  sig { params(target: Organization).returns(T.nilable(SecurityConfiguration)) }
  def duplicate_and_enable_code_scanning(target)
    # This configuration already has Code Scanning enabled!
    return nil if code_scanning_enabled?

    duplicate_and_enable_feature(
      target:,
      name_suffix: "with Code Security",
      existing_scope: T.cast(self.class, T.class_of(SecurityConfiguration)).code_scanning_enabled,
      build_target_attributes: ->(t, n) { attributes_for_duplication_and_code_scanning_enablement(target: t, name: n) },
      compare_attributes: ->(config) { config.attributes_for_duplication_and_code_scanning_enablement },
    )
  end

  # See UnbundledSecurityConfiguration#attributes_for_duplication_and_code_scanning_enablement
  # for behavior when the security configuration belongs to an organization on unbundled GHAS.
  sig { overridable.params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_code_scanning_enablement(target: self.target, name: self.name)
    {
      target:,
      name:,
      enable_ghas: true,
      code_scanning: "enabled",
      code_scanning_delegated_alert_dismissal:,
      code_scanning_options: { "allow_advanced" => true },
      dependabot_alerts:,
      dependabot_security_updates:,
      dependabot_malware_alerts:,
      dependency_graph:,
      dependency_graph_autosubmit_action:,
      dependency_graph_autosubmit_action_options:,
      private_vulnerability_reporting:,
      secret_scanning:,
      secret_scanning_delegated_alert_dismissal:,
      secret_scanning_delegated_bypass:,
      secret_scanning_generic_secrets:,
      secret_scanning_non_provider_patterns:,
      secret_scanning_push_protection:,
      secret_scanning_validity_checks:,
    }
  end

  private

  sig do
    params(
      target: Organization,
      name_suffix: String,
      existing_scope: T.untyped,
      build_target_attributes: T.proc.params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]),
      compare_attributes: T.proc.params(config: SecurityConfiguration).returns(T::Hash[Symbol, T.untyped]),
    ).returns(T.nilable(SecurityConfiguration))
  end
  def duplicate_and_enable_feature(target:, name_suffix:, existing_scope:, build_target_attributes:, compare_attributes:)
    new_name = "#{name} (#{name_suffix})"
    target_attributes = build_target_attributes.call(target, new_name)

    # Reuse an existing configuration if its attributes already match
    existing_scope.where(target:).find_each do |config|
      return config if target_attributes == compare_attributes.call(config)
    end

    if SecurityConfiguration.where(target:, name: new_name).exists?
      new_name = "#{name} (#{name_suffix} - #{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")})"
      target_attributes[:name] = new_name
    end

    with_write do
      new_config = T.cast(self.class, T.class_of(SecurityConfiguration)).new(target_attributes)
      new_config.description = description
      new_config.save!

      if enforced?(target)
        SecurityConfigurationPolicy.create_or_update(
          target: target,
          enforcement: SecurityConfigurationPolicy::Enforcement::Enforced,
          security_configuration_id: new_config.id,
        )
      end

      new_config
    end
  end
end
