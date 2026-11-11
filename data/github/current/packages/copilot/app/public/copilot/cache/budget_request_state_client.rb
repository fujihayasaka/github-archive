# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    # Caches the per-user-per-org budget request state (e.g. "post_request",
    # "request_denied") written by the BudgetRequestsController. The banner
    # component reads this to decide which banner variant to render.
    #
    # Backed by GitHub::RemoteCache (Global Cache / replicated Redis).
    class BudgetRequestStateClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = T.let(:copilot_budget_request_state, Symbol)
      DEFAULT_TTL = T.let(30.days.to_i, Integer)

      SourceKeyType = type_member { { fixed: [Integer, Integer] } }
      SourceValueType = type_member { { fixed: T.nilable(T::Hash[String, T.untyped]) } } # rubocop:disable Sorbet/ForbidTUntyped

      sig { params(user_id: Integer, org_id: Integer).void }
      def initialize(user_id:, org_id:)
        @user_id = user_id
        @org_id = org_id
      end

      sig { override.returns(Symbol) }
      def cache_key_name
        CACHE_KEY_NAME
      end

      sig { override.params(source_key: SourceKeyType).returns(String) }
      def cache_key_id(source_key)
        user_id, org_id = source_key
        "user:#{user_id}:org:#{org_id}"
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        [[@user_id, @org_id]]
      end

      sig { override.returns(T::Boolean) }
      def enabled?
        true
      end

      sig { override.returns(SourceValueType) }
      def fallback
        nil
      end

      sig { override.returns(GitHub::RemoteCache::Serializer[SourceValueType]) }
      def serializer
        Copilot::Cache::BudgetRequestStateSerializer
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        DEFAULT_TTL
      end

      sig { override.returns(T::Array[T.class_of(StandardError)]) }
      def resilience_error_types
        []
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
