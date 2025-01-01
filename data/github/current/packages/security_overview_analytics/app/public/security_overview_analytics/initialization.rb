# typed: strict
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  class Initialization
    extend T::Sig
    include GitHub::Memoizer

    sig { returns(ScopeStrategy::Base) }
    attr_reader :strategy

    sig do
      params(
        scope: T.any(::Business, ::User),
        prerequisite: T.nilable(Type)
      ).returns(Initialization)
    end
    def self.for(scope, prerequisite: nil)
      if scope.is_a?(::Business)
        return new(strategy: ScopeStrategy::Business.new(business: scope, prerequisite:))
      elsif scope.is_a?(::Organization)
        return new(strategy: ScopeStrategy::Organization.new(organization: scope))
      elsif scope.is_a?(::User)
        return new(strategy: ScopeStrategy::User.new(user: scope))
      end

      T.absurd(scope)
    end

    sig { returns(T::Array[SecurityOverviewAnalytics::Initialization::Type]) }
    def initialization_types
      @strategy.initialization_types
    end

    private_class_method :new
    sig { params(strategy: ScopeStrategy::Base).void }
    def initialize(strategy:)
      @strategy = strategy
    end

    sig { params(type: T.nilable(Initialization::Type)).void }
    def enqueue(type: nil)
      strategy.enqueue(type:)
    end

    sig { params(type: Type).returns(T::Boolean) }
    def initialized?(type:)
      SecurityCenter::KV.store.exists(initialization_kv_key(type:)).value { false }
    end

    sig { returns(T::Boolean) }
    def all_initialized?
      SecurityCenter::KV.store.mexists(available_metric_keys).value { [false] }.all?
    end

    sig { returns(T::Boolean) }
    def any_uninitialized?
      SecurityCenter::KV.store.mexists(available_metric_keys).value { [false] }.include?(false)
    end

    sig { returns(T::Boolean) }
    def any_initialized?
      SecurityCenter::KV.store.mexists(available_metric_keys).value { [false] }.any?
    end

    sig { void }
    def set_all_to_initialized
      available_metric_keys.each do |key|
        set_initialized(key: key)
      end
    end

    sig { params(type: Type).void }
    def set_type_to_initialized(type:)
      return unless feature_enabled?(type)
      set_initialized(key: initialization_kv_key(type:))
    end

    sig { void }
    def delete_all_initializations
      SecurityCenter::KV.store.mdel_prefix(strategy.initialization_key_prefix)
    end

    sig { params(type: Type).void }
    def delete_initialization(type:)
      SecurityCenter::KV.store.del(initialization_kv_key(type:))
    end

    # DO NOT REMOVE entire function on feature flag removal.
    # This pattern should remain in case we add another entity type in future.
    sig { params(type: Type).returns(T::Boolean) }
    def feature_enabled?(type)
      true
    end

    protected

    sig { params(key: String).void }
    def set_initialized(key:)
      SecurityCenter::KV.store.set(key, "true")
    end

    sig { params(type: Type).returns(String) }
    def initialization_kv_key(type:)
      "#{strategy.initialization_key_prefix}.#{type.serialize}"
    end

    sig { params(str: T.nilable(String)).returns(Type) }
    def deserialize_to_type(str)
      return Type::Unknown if str.blank?

      Type.deserialize(str)
    rescue ::KeyError => e
      log_hash = {
        "gh.security_overview_analytics.initialization.invalid_input" => str,
        "gh.security_overview_analytics.initialization.initialization_key_prefix" => strategy.initialization_key_prefix
      }

      if strategy.is_a?(ScopeStrategy::Business)
        log_hash["gh.business.id"] = strategy.try(:business).try(:id)
      elsif strategy.is_a?(ScopeStrategy::Organization)
        log_hash["gh.org.id"] = strategy.try(:organization).try(:id)
      elsif strategy.is_a?(ScopeStrategy::User)
        log_hash["gh.user.id"] = strategy.try(:user).try(:id)
      end

      GitHub.logger.warn(
        "String could not be deserialized into a Type: #{e.message}",
        **log_hash
      )

      Type::Unknown
    end

    sig { returns(T::Array[String]) }
    def available_metric_keys
      initialization_types.reduce(T.let([], T::Array[String])) do |memo, type|
        next memo unless feature_enabled?(type)
        memo << initialization_kv_key(type:)
        memo
      end
    end
  end
end
