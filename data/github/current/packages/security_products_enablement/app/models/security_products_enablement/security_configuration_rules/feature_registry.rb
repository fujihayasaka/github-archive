# typed: strict
# frozen_string_literal: true

# Declarative registry of security configuration features, SKUs, and enablement levels.
#
# Each FEATURES entry defines:
#   parent        – direct parent feature (nil for roots). Drives Rules 1 & 2.
#   sku           – licensing gate (:code_security or :secret_protection). Drives Rule 3.
#   sku_policy    – client cascade behavior when a SKU toggle changes (Rule 3 cascade).
#   error_message – verbatim string used by the server when the hierarchy invariant is violated.
class SecurityProductsEnablement::SecurityConfigurationRules::FeatureRegistry
  class Sku < T::Enum
    enums do
      CodeSecurity = new(:code_security)
      SecretProtection = new(:secret_protection)
    end
  end

  class SkuPolicy < T::Enum
    enums do
      # Feature is force-enabled when its SKU is turned on
      EnableOnSku = new(:enable_on_sku)
      # Feature preserves its current value if already enabled, otherwise defaults to not_set
      PreserveOnSku = new(:preserve_on_sku)
      # Feature is enabled if recommended on this instance, otherwise defaults to not_set
      RecommendOnSku = new(:recommend_on_sku)
    end
  end

  class Feature < T::Struct
    const :parent, T.nilable(Symbol)
    const :sku, T.nilable(Sku)
    const :sku_policy, T.nilable(SkuPolicy)
    const :error_message, T.nilable(String)
  end

  FEATURES = T.let({
    # ── Secret Scanning ─────────────────────────
    secret_scanning: Feature.new(
      parent:        nil,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::EnableOnSku,
      error_message: nil,
    ),
    secret_scanning_push_protection: Feature.new(
      parent:        :secret_scanning,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::EnableOnSku,
      error_message: "Push protection must be disabled when secret scanning is disabled",
    ),
    secret_scanning_delegated_bypass: Feature.new(
      parent:        :secret_scanning_push_protection,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::PreserveOnSku,
      error_message: "Delegated bypass must be disabled when push protection is disabled",
    ),
    secret_scanning_validity_checks: Feature.new(
      parent:        :secret_scanning,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::RecommendOnSku,
      error_message: "Validity checks must be disabled when secret scanning is disabled",
    ),
    secret_scanning_extended_metadata: Feature.new(
      parent:        :secret_scanning_validity_checks,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::RecommendOnSku,
      error_message: "Extended metadata must be disabled when validity checks is disabled",
    ),
    secret_scanning_non_provider_patterns: Feature.new(
      parent:        :secret_scanning,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::EnableOnSku,
      error_message: "Non-provider patterns must be disabled when secret scanning is disabled",
    ),
    secret_scanning_generic_secrets: Feature.new(
      parent:        :secret_scanning,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::PreserveOnSku,
      error_message: "Generic Secrets must be disabled when secret scanning is disabled",
    ),
    secret_scanning_delegated_alert_dismissal: Feature.new(
      parent:        :secret_scanning,
      sku:           Sku::SecretProtection,
      sku_policy:    SkuPolicy::PreserveOnSku,
      error_message: "Delegated alert dismissal must be disabled when secret scanning is disabled",
    ),

    # ── Code Scanning ───────────────────────────
    code_scanning: Feature.new(
      parent:        nil,
      sku:           Sku::CodeSecurity,
      sku_policy:    SkuPolicy::EnableOnSku,
      error_message: nil,
    ),
    code_scanning_delegated_alert_dismissal: Feature.new(
      parent:        nil,
      sku:           Sku::CodeSecurity,
      sku_policy:    SkuPolicy::PreserveOnSku,
      error_message: nil,
    ),

    # ── Dependency Graph / Dependabot ───────────
    dependency_graph: Feature.new(
      parent:        nil,
      sku:           nil,
      sku_policy:    nil,
      error_message: nil,
    ),
    dependency_graph_autosubmit_action: Feature.new(
      parent:        :dependency_graph,
      sku:           nil,
      sku_policy:    nil,
      error_message: "Automatic dependency submission must be disabled when Dependency graph is disabled",
    ),
    dependabot_alerts: Feature.new(
      parent:        :dependency_graph,
      sku:           nil,
      sku_policy:    nil,
      error_message: "Dependabot alerts must be disabled when Dependency graph is disabled",
    ),
    dependabot_security_updates: Feature.new(
      parent:        :dependabot_alerts,
      sku:           nil,
      sku_policy:    nil,
      error_message: "Dependabot security updates must be disabled when Dependabot alerts are disabled",
    ),
    dependabot_delegated_alert_dismissal: Feature.new(
      parent:        :dependabot_alerts,
      sku:           Sku::CodeSecurity,
      sku_policy:    SkuPolicy::PreserveOnSku,
      error_message: "Delegated alert dismissal must be disabled when Dependabot alerts are disabled",
    ),
    dependabot_malware_alerts: Feature.new(
      parent:        :dependabot_alerts,
      sku:           nil,
      sku_policy:    nil,
      error_message: "Malware alerts must be disabled when Dependabot alerts are disabled",
    ),

    # ── Other ───────────────────────────────────
    private_vulnerability_reporting: Feature.new(
      parent:        nil,
      sku:           nil,
      sku_policy:    nil,
      error_message: nil,
    ),
  }.freeze, T::Hash[Symbol, Feature])

  SKUS = T.let([Sku::CodeSecurity, Sku::SecretProtection].freeze, T::Array[Sku])

  # Returns feature keys that require the given SKU.
  sig { params(sku: Sku).returns(T::Array[Symbol]) }
  def self.features_for_sku(sku)
    FEATURES.select { |_, f| f.sku == sku }.keys.freeze
  end

  # Returns all feature keys that require any paid SKU (i.e. non-free features).
  sig { returns(T::Array[Symbol]) }
  def self.paid_features
    FEATURES.select { |_, f| f.sku }.keys.freeze
  end

  # Returns all feature keys in the registry.
  sig { returns(T::Array[Symbol]) }
  def self.all_feature_keys
    FEATURES.keys.freeze
  end

  # Returns the ancestor feature keys for the given feature, walking up the parent chain.
  sig { params(feature: Symbol).returns(T::Array[Symbol]) }
  def self.ancestors_of(feature)
    result = T.let([], T::Array[Symbol])
    parent = T.let(FEATURES[feature]&.parent, T.nilable(Symbol))
    while parent
      result << parent
      parent = FEATURES[parent]&.parent
    end
    result
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def self.as_json
    features = FEATURES.transform_values do |feature|
      entry = {
        "parent" => feature.parent&.to_s&.camelize(:lower),
        "sku" => feature.sku&.serialize&.to_s,
      }

      sku_policy = feature.sku_policy
      if sku_policy
        entry["skuPolicy"] = sku_policy.serialize.to_s
      end

      entry
    end

    {
      "features" => features.transform_keys { |k| k.to_s.camelize(:lower) },
      "skus" => SKUS.map { |sku| sku.serialize.to_s },
    }
  end
end
