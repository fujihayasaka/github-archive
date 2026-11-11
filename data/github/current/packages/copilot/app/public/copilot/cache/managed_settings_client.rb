# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    # Caches the contents of the Copilot managed-settings JSON file
    # (.github/copilot/settings.json on the enterprise's source repo) so that
    # `GET /copilot_internal/managed_settings` does not have to hit git RPC on
    # every request.
    #
    # Backed by GitHub::RemoteCache (Redis). On stamps where RemoteCache has no
    # store configured (Azure regions, Proxima today), `fetch` falls through to
    # the block on every call — i.e. no caching, but no incorrect behavior.
    class ManagedSettingsClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = :copilot_managed_settings
      FEATURE_FLAG = T.let("copilot_managed_settings_cache".freeze, String)
      # Opt-out, business-level feature flag that bypasses the cache for the
      # `GET /copilot_internal/managed_settings` endpoint. When enabled, the
      # endpoint force-refreshes the cache on every request so that local
      # development against a test enterprise does not have to wait for the
      # cache TTL to expire when iterating on the managed-settings JSON file.
      BYPASS_FEATURE_FLAG = T.let("copilot_managed_settings_cache_bypass".freeze, String)

      # Sentinel stored when the source file is missing, so that "not found"
      # is also cached and we do not retry the git read on every request.
      # Also used as the fallback returned on cache infrastructure errors.
      NOT_FOUND_SENTINEL = T.let("__copilot_managed_settings_not_found__".freeze, String)

      TTL_BASE = T.let(5.minutes.to_i, Integer)
      TTL_JITTER_FACTOR = T.let(0.2, Float)

      SourceKeyType = type_member { { fixed: Integer } }
      SourceValueType = type_member { { fixed: String } }

      sig { params(enterprise: ::Business).void }
      def initialize(enterprise:)
        @enterprise = enterprise
      end

      sig { override.returns(Symbol) }
      def cache_key_name
        CACHE_KEY_NAME
      end

      sig { override.params(source_key: SourceKeyType).returns(String) }
      def cache_key_id(source_key)
        "business:#{source_key}"
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        [@enterprise.id]
      end

      sig { override.returns(T::Boolean) }
      def enabled?
        true
      end

      sig { override.returns(SourceValueType) }
      def fallback
        NOT_FOUND_SENTINEL
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        Copilot::Cache::ManagedSettingsSerializer
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        # It produces a TTL randomly within ±TTL_JITTER_FACTOR (a percentage) of the base TTL.
        jitter_multiplier = Kernel.rand((1.0 - TTL_JITTER_FACTOR)..(1.0 + TTL_JITTER_FACTOR))
        (TTL_BASE * jitter_multiplier).round
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
      end

      sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
      def rollout_mode
        GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
      end

      sig { override.returns(T.nilable(GitHub::RemoteCache::StalenessObserver[SourceValueType])) }
      def staleness_observer
        nil
      end

      private

      sig { override.returns(GitHub::RemoteCache::Client) }
      def cache_client
        Copilot::Cache.client
      end
    end
  end
end
