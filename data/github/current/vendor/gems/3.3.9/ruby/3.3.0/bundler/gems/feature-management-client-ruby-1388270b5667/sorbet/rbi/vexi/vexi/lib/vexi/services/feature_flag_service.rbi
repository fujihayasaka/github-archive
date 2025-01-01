# frozen_string_literal: true
# typed: strict

module Vexi
  # Public: Vexi services.
  module Services
    # Public: Feature Flag Service responsible for fetching feature flags from the cache or adapter.
    class FeatureFlagService < AbstractEntityService
      extend T::Sig
      extend T::Helpers
      extend T::Generic # Provides `type_member` helper

      sig {
        params(
          adapter: Adapter,
          cache_config: T.nilable(CacheConfig),
          adapter_breaker: T.nilable(Resilient::CircuitBreaker),
          cache_breaker: T.nilable(Resilient::CircuitBreaker)
        ).void
      }
      def initialize(adapter, cache_config = nil, adapter_breaker = nil, cache_breaker = nil); end

      sig { override.returns(T::Class[EntityType]) }
      def entity_type; end

      sig { override.returns(String) }
      def entity_type_name; end

      private

      sig { override.params(name: String).returns(String) }
      def get_cache_key(name); end

      sig do
        override.params(names: T::Array[String]).returns(T::Array[GetEntityResponse])
      end
      def get_entity_responses(names); end

      sig { override.params(name: String).returns(EntityType) }
      def get_default_entity_instance(name); end
    end
  end
end
