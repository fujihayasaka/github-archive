# typed: strict
# frozen_string_literal: true

### A cache to store the timestamp of the last subscription attempt for a given user
### This is used to determine whether a subscription attempt was made recently enough to consider a new transaction as a new purchase or an upgrade rather than a recurring charge
module Copilot
  module Cache
    class SubscriptionAttemptedAtClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = :copilot_subscription_attempted

      SourceKeyType = type_member { { fixed: Integer } }
      SourceValueType = type_member { { fixed: Integer } }

      sig do
        params(user: ::User).void
      end
      def initialize(user:)
        @user = T.let(user, ::User)
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
        !!@user.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false)
      end

      sig { override.returns(SourceValueType) }
      def fallback
        0
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        GitHub::RemoteCache::NumericSerializer
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        [@user.id]
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        12.hours.to_i
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
      end

      sig { override.returns(GitHub::RemoteCache::Client::RolloutMode) }
      def rollout_mode
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
