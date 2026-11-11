# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    class SeatsCheckClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = :copilot_seats_check
      FALLBACK       = T.let(:NOT_EVALUATED, Symbol)

      SourceKeyType = type_member { { fixed: Integer } }
      SourceValueType = type_member { { fixed: Symbol } }

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
        !!@users.first&.feature_flag_enabled?(:use_copilot_access_type_caches, default: false)
      end

      sig { override.returns(SourceValueType) }
      def fallback
        FALLBACK
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        GitHub::RemoteCache::SymbolSerializer
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        @users.map(&:id)
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        if FeatureFlag.vexi.enabled?(:seats_check_cache_short_ttl, default: false)
          5.minutes.to_i
        else
          1.hour.to_i
        end
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
      end

      sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
      def rollout_mode
        return GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithExtendedTelemetry if @users.first&.feature_flag_enabled?(:seats_check_cache_extended_telemetry, default: false)
        GitHub::RemoteCache::Client::RolloutMode::ReturnCacheValueWithBaseTelemetry
      end

      sig { override.returns(GitHub::RemoteCache::StalenessObserver[SourceValueType]) }
      def staleness_observer
        GitHub::RemoteCache::PrimitiveValueStalenessObserver
      end

      private

      sig { override.returns(GitHub::RemoteCache::Client) }
      def cache_client
        Copilot::Cache.client
      end
    end
  end
end
