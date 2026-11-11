# typed: strict
# frozen_string_literal: true

# Validates a SecurityConfiguration against the feature dependency tree and SKU gates
# defined in FeatureRegistry.
#
# Five rules govern feature/SKU interactions:
#
#   Rule 1 – Parent → child clamp: a child's enablement level cannot exceed
#            its parent's. Ordering: disabled < not_set < enabled.
#   Rule 2 – Child → parent pull-up: same invariant as Rule 1, enforced from
#            the child direction. No separate server logic needed.
#   Rule 3 – SKU → feature clamp: paid features cannot be enabled without
#            their SKU toggle. Bundled configs use enable_ghas; unbundled
#            configs use per-SKU booleans (code_security_sku_enabled,
#            secret_protection_sku_enabled).
#   Rule 4 – Feature → SKU pull-up: client-only (no server validation).
#   Rule 5 – Options preservation: cascades never modify feature options.
#            Client-only; no server logic.
#
# Errors accumulate — the validator evaluates every rule and collects all
# violations before returning.
class SecurityProductsEnablement::SecurityConfigurationRules::FeatureValidator
  Registry = SecurityProductsEnablement::SecurityConfigurationRules::FeatureRegistry

  # Enablement level ordering for the hierarchy invariant (Rules 1 & 2).
  # A child's level cannot exceed its parent's.
  # disabled < not_set < enabled — intentionally differs from the DB integer ordering
  # (disabled=0, enabled=1, not_set=2).
  ENABLEMENT_LEVELS = T.let({
    "disabled" => 0,
    "not_set" => 1,
    "enabled" => 2,
  }.freeze, T::Hash[String, Integer])

  sig { params(config: SecurityConfiguration).void }
  def initialize(config)
    @config = config
    @errors = T.let({}, T::Hash[Symbol, T::Array[String]])
  end

  sig { params(config: SecurityConfiguration).returns(T::Hash[Symbol, T::Array[String]]) }
  def self.compute_errors(config)
    new(config).compute_errors
  end

  # Evaluates all validation rules against the config and returns accumulated errors.
  # Does not mutate the config.
  sig { returns(T::Hash[Symbol, T::Array[String]]) }
  def compute_errors
    validate_hierarchy

    if @config.instance_of?(SecurityConfiguration)
      validate_bundled_sku_gates
    else
      validate_unbundled_sku_gates
    end

    @errors
  end

  private

  # Rules 1 & 2 ("Parent → child clamp" / "Child → parent pull-up").
  # The hierarchy invariant: a child's enablement level cannot exceed its parent's.
  # For each feature with a parent, reject if child_level > parent_level.
  # nil feature values are treated as disabled (level 0).
  sig { void }
  def validate_hierarchy
    Registry::FEATURES.each do |feature_key, feature|
      parent_key = feature.parent
      next if parent_key.nil?

      error_message = feature.error_message
      next if error_message.nil?

      child_level = enablement_level(feature_key)
      parent_level = enablement_level(parent_key)

      if child_level > parent_level
        add_error(feature_key, error_message)
      end
    end
  end

  # Rule 3 ("SKU → feature clamp") for bundled configs.
  # Bundled configs use enable_ghas as the single gate for all paid features.
  # Also enforces mutual-exclusion: unbundled SKU fields must not be set.
  sig { void }
  def validate_bundled_sku_gates
    if @config.code_security_sku_enabled
      add_error(:code_security_sku_enabled,
        "This entity is not eligible to use the GitHub Code Security product. Use `enable_ghas` instead.")
    end

    if @config.secret_protection_sku_enabled
      add_error(:secret_protection_sku_enabled,
        "This entity is not eligible to use the GitHub Secret Protection product. Use `enable_ghas` instead.")
    end

    return if @config.enable_ghas

    # GHAS is off: no SKU-gated feature may be enabled or not_set.
    paid_feature_keys = Registry::FEATURES.filter_map { |key, f| key unless f.sku.nil? }
    return unless paid_feature_keys.any? { |key| !@config.feature_nil_or_disabled?(key) }

    readable_list = paid_feature_keys.map { |k| k.to_s.humanize }.join(", ")
    add_error(:enable_ghas,
      "#{readable_list} must be disabled when GitHub Advanced Security is disabled")
  end

  # Rule 3 ("SKU → feature clamp") for unbundled configs.
  # Unbundled configs use per-SKU booleans (code_security_sku_enabled,
  # secret_protection_sku_enabled) as tristate gates:
  #   true  → paid features may be enabled
  #   false → all features for that SKU must be disabled/nil
  #   nil   → features may be disabled or not_set, but not enabled
  # Also enforces mutual-exclusion: enable_ghas must not be set.
  sig { void }
  def validate_unbundled_sku_gates
    if @config.enable_ghas
      add_error(:enable_ghas,
        "This entity is not eligible to use the bundled GitHub Advanced Security product. " \
        "Use `code_security_sku_enabled` and `secret_protection_sku_enabled` instead.")
    end

    Registry::SKUS.each do |sku|
      toggle_field = sku_toggle_field(sku)
      sku_value = @config[toggle_field]
      sku_name = sku_human_name(sku)

      sku_feature_keys = Registry::FEATURES.filter_map { |key, f| key if f.sku == sku }
      next if sku_feature_keys.empty?

      if sku_value == false
        # SKU explicitly disabled: all features must be nil or disabled
        next unless sku_feature_keys.any? { |key| !@config.feature_nil_or_disabled?(key) }

        readable_list = sku_feature_keys.map { |k| k.to_s.humanize }.join(", ")
        add_error(toggle_field,
          "#{readable_list} must be disabled when #{sku_name} is disabled")
      elsif sku_value.nil?
        # SKU unset: features cannot be enabled (only disabled or not_set)
        next unless sku_feature_keys.any? { |key| @config.feature_enabled?(key) }

        readable_list = sku_feature_keys.map { |k| k.to_s.humanize }.join(", ")
        add_error(toggle_field,
          "#{readable_list} cannot be enabled when #{sku_name} is not enabled")
      end
    end
  end

  sig { params(feature_key: Symbol).returns(Integer) }
  def enablement_level(feature_key)
    value = @config[feature_key]
    return 0 unless value.is_a?(String)
    ENABLEMENT_LEVELS.fetch(value, 0)
  end

  sig { params(key: Symbol, message: String).void }
  def add_error(key, message)
    existing = @errors[key]
    if existing
      existing << message
    else
      @errors[key] = [message]
    end
  end

  sig { params(sku: Registry::Sku).returns(Symbol) }
  def sku_toggle_field(sku)
    case sku
    when Registry::Sku::CodeSecurity then :code_security_sku_enabled
    when Registry::Sku::SecretProtection then :secret_protection_sku_enabled
    else T.absurd(sku)
    end
  end

  sig { params(sku: Registry::Sku).returns(String) }
  def sku_human_name(sku)
    case sku
    when Registry::Sku::CodeSecurity then "Code Security"
    when Registry::Sku::SecretProtection then "Secret Protection"
    else T.absurd(sku)
    end
  end
end
