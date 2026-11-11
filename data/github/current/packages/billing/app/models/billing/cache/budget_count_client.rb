# typed: strict
# frozen_string_literal: true

class Billing::Cache::BudgetCountClient
  extend T::Generic
  include GitHub::RemoteCache::Preset

  SourceKeyType = type_member { { fixed: [String, T.nilable(String), T.nilable(String), T.nilable(T::Array[String]), T.nilable(T::Array[String])] } }
  SourceValueType = type_member { { fixed: Integer } }

  # All known scope values used in budget queries.
  SCOPES = T.let(
    [nil, "enterprise", "organization", "org", "repository", "repo", "user", "cost_center", "cost-center"].freeze,
    T::Array[T.nilable(String)],
  )

  # Builds a client that targets all (scope, exclude_scope) combinations for a customer.
  # Used for batch invalidation after budget mutations.
  #
  # NOTE: This only invalidates singular scope/exclude_scope cache entries.
  # Multi-scope array entries (scopes/exclude_scopes) are NOT proactively invalidated.
  sig { params(customer_id: String, feature_flag_target: T.nilable(T.any(User, Organization, Business))).returns(Billing::Cache::BudgetCountClient) }
  def self.for_all_scopes(customer_id, feature_flag_target: nil)
    keys = T.let([], T::Array[[String, T.nilable(String), T.nilable(String), T.nilable(T::Array[String]), T.nilable(T::Array[String])]])
    SCOPES.each do |scope|
      SCOPES.each do |exclude_scope|
        next if scope == exclude_scope && !scope.nil?
        keys << [customer_id, scope, exclude_scope, nil, nil]
      end
    end
    new(customer_id, feature_flag_target: feature_flag_target, all_source_keys: keys)
  end

  sig { params(customer_id: String, scope: T.nilable(String), exclude_scope: T.nilable(String), scopes: T.nilable(T::Array[String]), exclude_scopes: T.nilable(T::Array[String]), feature_flag_target: T.nilable(T.any(User, Organization, Business)), all_source_keys: T.nilable(T::Array[SourceKeyType])).void }
  def initialize(customer_id, scope = nil, exclude_scope = nil, scopes: nil, exclude_scopes: nil, feature_flag_target: nil, all_source_keys: nil)
    @customer_id = customer_id
    @scope = scope
    @exclude_scope = exclude_scope
    @scopes = T.let(scopes, T.nilable(T::Array[String]))
    @exclude_scopes = T.let(exclude_scopes, T.nilable(T::Array[String]))
    @feature_flag_target = T.let(feature_flag_target, T.nilable(T.any(User, Organization, Business)))
    @all_source_keys = T.let(all_source_keys, T.nilable(T::Array[SourceKeyType]))
  end

  sig { override.returns(Symbol) }
  def cache_key_name
    :budget_count
  end

  sig { override.params(source_key: SourceKeyType).returns(String) }
  def cache_key_id(source_key)
    customer_id, scope, exclude_scope, scopes, exclude_scopes = source_key
    key_parts = ["v1", "customer_id", customer_id]
    if scopes.present?
      key_parts << "scopes_#{scopes.sort.join(',')}"
    elsif scope.present?
      key_parts << "scope_#{scope}"
    end
    if exclude_scopes.present?
      key_parts << "exclude_scopes_#{exclude_scopes.sort.join(',')}"
    elsif exclude_scope.present?
      key_parts << "exclude_#{exclude_scope}"
    end
    key_parts.join(":")
  end

  sig { override.returns(T::Array[SourceKeyType]) }
  def source_keys
    @all_source_keys || [[@customer_id, @scope, @exclude_scope, @scopes, @exclude_scopes]]
  end

  sig { override.returns(Integer) }
  def ttl
    5.minutes.to_i
  end

  # Feature flag is checked at call site before instantiation.
  # This client is always enabled once instantiated.
  sig { override.returns(T::Boolean) }
  def enabled?
    true
  end

  # Sentinel value: the client skips writes for nil, so use -1
  # to indicate "no count available" on error.
  FALLBACK_VALUE = T.let(-1, Integer)

  sig { override.returns(SourceValueType) }
  def fallback
    FALLBACK_VALUE
  end

  sig { override.returns(T::Array[T.class_of(StandardError)]) }
  def resilience_error_types
    []
  end

  sig { override.returns(T.class_of(GitHub::RemoteCache::NumericSerializer)) }
  def serializer
    GitHub::RemoteCache::NumericSerializer
  end

  sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
  def staleness_observer
    GitHub::RemoteCache::PrimitiveValueStalenessObserver
  end

  sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def staleness_context
    { customer_id: @customer_id, scope: @scope, exclude_scope: @exclude_scope, scopes: @scopes, exclude_scopes: @exclude_scopes }
  end

  # Rollout progression:
  # 1. Default: ReturnSourceValueWithExtendedTelemetry (validate correctness)
  # 2. :billing_budget_count_cache_return_cached → ReturnCacheValueWithBaseTelemetry
  sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
  def rollout_mode
    if FeatureFlag.vexi.enabled?(:billing_budget_count_cache_return_cached, @feature_flag_target, default: false)
      GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
    else
      GitHub::RemoteCache::Client::RolloutMode::ReturnSourceValueWithExtendedTelemetry
    end
  end

  private

  sig { override.returns(GitHub::RemoteCache::Client) }
  def cache_client
    Billing::Cache.client
  end
end
