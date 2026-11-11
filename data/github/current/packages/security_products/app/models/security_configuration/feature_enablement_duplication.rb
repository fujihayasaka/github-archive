# typed: strict
# frozen_string_literal: true

# Encapsulates configuration duplication logic used by risk-assessment workflows
# to create derived configs with specific security features (e.g. Code Security,
# Secret Protection) enabled.
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
      existing_scope: klass.secret_scanning_enabled,
      build_target_attributes: ->(t, n) { attributes_for_duplication_and_secret_scanning_enablement(target: t, name: n) },
      compare_attributes: ->(config) { config.attributes_for_duplication_and_secret_scanning_enablement },
    )
  end

  sig { params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_secret_scanning_enablement(target: self.target, name: self.name)
    overrides = {
      secret_scanning: "enabled",
      secret_scanning_push_protection: "enabled",
    }
    if bundled?
      overrides[:enable_ghas] = true
    else
      overrides[:enable_ghas] = false
      overrides[:secret_protection_sku_enabled] = true
    end
    base_duplication_attributes(target:, name:).merge(overrides)
  end

  sig { params(target: Organization).returns(T.nilable(SecurityConfiguration)) }
  def duplicate_and_enable_code_scanning(target)
    # This configuration already has Code Scanning enabled!
    return nil if code_scanning_enabled?

    duplicate_and_enable_feature(
      target:,
      name_suffix: "with Code Security",
      existing_scope: klass.code_scanning_enabled,
      build_target_attributes: ->(t, n) { attributes_for_duplication_and_code_scanning_enablement(target: t, name: n) },
      compare_attributes: ->(config) { config.attributes_for_duplication_and_code_scanning_enablement },
    )
  end

  sig { params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  protected def attributes_for_duplication_and_code_scanning_enablement(target: self.target, name: self.name)
    overrides = {
      code_scanning: "enabled",
      code_scanning_options: { "allow_advanced" => true },
    }
    if bundled?
      overrides[:enable_ghas] = true
    else
      overrides[:enable_ghas] = false
      overrides[:code_security_sku_enabled] = true
    end
    base_duplication_attributes(target:, name:).merge(overrides)
  end

  private

  # Returns the concrete class (SecurityConfiguration or UnbundledSecurityConfiguration)
  # so that .new and scope methods preserve STI type.
  sig { returns(T.class_of(SecurityConfiguration)) }
  def klass
    T.cast(self, SecurityConfiguration).class
  end

  # Builds a hash of all feature attributes from the current config using the
  # FeatureRegistry as the source of truth. Callers merge feature-specific
  # overrides (e.g. secret_scanning: "enabled") on top of this base.
  sig { params(target: Organization, name: String).returns(T::Hash[Symbol, T.untyped]) }
  def base_duplication_attributes(target:, name:)
    attrs = T.let({ target:, name: }, T::Hash[Symbol, T.untyped])

    SecurityConfiguration::ALL_FEATURES_WITH_SKUS.each { |f| attrs[f] = read_attribute(f) }
    SecurityConfiguration::FEATURE_OPTIONS.each_key { |opt| attrs[opt] = read_attribute(opt) }

    attrs
  end

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
      new_config = klass.new(target_attributes)
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
