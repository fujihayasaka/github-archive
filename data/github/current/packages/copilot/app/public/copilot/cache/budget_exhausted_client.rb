# typed: strict
# frozen_string_literal: true

module Copilot
  module Cache
    # Caches per-user "budget exhausted" signals written by the
    # BudgetThresholdNotificationProcessor stream processor. The banner
    # component reads this to decide whether to show the Copilot budget
    # request banner.
    #
    # The cached value is a structured array of budget entries — one per org
    # whose budget has been exhausted for this user. This allows a single user
    # to have exhausted budgets across multiple organizations without overwriting.
    #
    # Backed by GitHub::RemoteCache (Global Cache / replicated Redis).
    # On stamps where RemoteCache has no store configured, `fetch` falls
    # through to the block on every call — no banner shown, no error.
    class BudgetExhaustedClient
      extend T::Generic
      include GitHub::RemoteCache::Preset

      CACHE_KEY_NAME = T.let(:copilot_budget_exhausted, Symbol)

      SourceKeyType = type_member { { fixed: Integer } }
      SourceValueType = type_member { { fixed: T.nilable(T::Array[T::Hash[String, T.untyped]]) } } # rubocop:disable Sorbet/ForbidTUntyped

      sig { params(user_id: Integer, ttl_seconds: T.nilable(Integer)).void }
      def initialize(user_id:, ttl_seconds: nil)
        @user_id = user_id
        @ttl_seconds = T.let(ttl_seconds || 1.day.to_i, Integer)
      end

      # Upserts a budget entry for a specific org into the cached array.
      # If an entry for the same org_id already exists, it is replaced.
      sig { params(entry: T::Hash[Symbol, T.any(Integer, String, T::Boolean)]).void }
      def upsert_entry(entry)
        entries = fetch_entries
        entries.reject! { |e| e["org_id"] == entry[:org_id] }
        entries << entry.transform_keys(&:to_s)
        store(entries)
      end

      # Removes a budget entry for a specific org from the cached array.
      # If the array becomes empty, the cache is invalidated entirely.
      sig { params(org_id: Integer).void }
      def remove_entry(org_id)
        entries = fetch_entries
        entries.reject! { |e| e["org_id"] == org_id }

        if entries.empty?
          invalidate
        else
          store(entries)
        end
      end

      # Returns all cached budget entries as an array of hashes.
      # Returns an empty array on cache miss.
      sig { returns(T::Array[T::Hash[String, T.untyped]]) } # rubocop:disable Sorbet/ForbidTUntyped
      def fetch_entries
        raw = fetch { nil }
        return [] if raw.nil?

        raw
      end

      sig { override.returns(Symbol) }
      def cache_key_name
        CACHE_KEY_NAME
      end

      sig { override.params(source_key: SourceKeyType).returns(String) }
      def cache_key_id(source_key)
        "user:#{source_key}"
      end

      sig { override.returns(T::Array[SourceKeyType]) }
      def source_keys
        [@user_id]
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
        Copilot::Cache::BudgetExhaustedSerializer
      end

      sig { override.returns(T.any(T.proc.params(arg0: SourceValueType).returns(Integer), Integer)) }
      def ttl
        @ttl_seconds
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
