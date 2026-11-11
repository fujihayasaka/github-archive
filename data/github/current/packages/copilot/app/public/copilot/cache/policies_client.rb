# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    class PoliciesClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = :copilot_policies
      FALLBACK       = T.let({}.freeze, T::Hash[Symbol, T.untyped])  # rubocop:disable Sorbet/ForbidTUntyped

      SourceKeyType = type_member { { fixed: Integer } }
      SourceValueType = type_member { { fixed: T::Hash[Symbol, T.untyped] } } # rubocop:disable Sorbet/ForbidTUntyped

      sig do
        params(user: T.any(::User, T::Array[::User])).void
      end
      def initialize(user:)
        @users = T.let(Array(user), T::Array[::User])
      end

      sig { override.params(source_key: SourceKeyType).returns(String) }
      def cache_key_id(source_key)
        "user_id:#{source_key}"
      end

      sig { override.returns(Symbol) }
      def cache_key_name
        CACHE_KEY_NAME
      end

      sig { override.returns(T::Boolean) }
      def enabled?
        true
      end

      sig { override.returns(SourceValueType) }
      def fallback
        FALLBACK
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        Copilot::Cache::PoliciesSerializer
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        @users.map(&:id).uniq
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        Copilot::CacheRefreshIntervalSetting.current_interval.to_i
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
      end

      sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
      def rollout_mode
        first_user = @users.first
        return GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry if first_user&.feature_flag_enabled?(:copilot_policies_cache_extended_telemetry, default: false)
        GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
      end

      sig { override.returns(T.nilable(GitHub::RemoteCache::StalenessObserver[SourceValueType])) }
      def staleness_observer
        Copilot::Cache::PoliciesStalenessObserver
      end

      private

      sig { override.returns(GitHub::RemoteCache::Client) }
      def cache_client
        Copilot::Cache.client
      end
    end
  end
end
