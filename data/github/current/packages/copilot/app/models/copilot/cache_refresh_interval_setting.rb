# typed: strict
# frozen_string_literal: true

module Copilot
  class CacheRefreshIntervalSetting
    CACHE_REFRESH_INTERVAL_KEY = "copilot:policy_cache:refresh_interval_seconds"

    DEFAULT_INTERVAL = T.let(12.hours, ActiveSupport::Duration)
    MIN_INTERVAL = T.let(5.minutes, ActiveSupport::Duration)
    MAX_INTERVAL = T.let(24.hours, ActiveSupport::Duration)
    FEATURE_FLAG = :copilot_policy_cache_dynamic_ttl

    class << self
      sig { returns(T::Boolean) }
      def enabled?
        FeatureFlag.vexi.enabled?(FEATURE_FLAG, default: false)
      end

      sig { returns(ActiveSupport::Duration) }
      def current_interval
        return DEFAULT_INTERVAL unless enabled?

        stored_interval || DEFAULT_INTERVAL
      end

      sig { returns(T.nilable(ActiveSupport::Duration)) }
      def stored_interval
        result = Copilot::KV.store.get(CACHE_REFRESH_INTERVAL_KEY)

        unless result.ok?
          log_kv_unavailable(result.error)
          return nil
        end

        value = result.value!
        return nil if value.nil? || value.empty?

        seconds = value.to_i
        return nil if seconds <= 0

        seconds.seconds
      end

      sig { params(seconds: Integer, actor: ::User, reason: String).returns(ActiveSupport::Duration) }
      def set!(seconds:, actor:, reason:)
        clamped = clamp(seconds)
        old_interval = stored_interval
        Copilot::KV.store.set(CACHE_REFRESH_INTERVAL_KEY, clamped.to_s)

        log_update(actor: actor, reason: reason, old_seconds: old_interval&.to_i, new_seconds: clamped)
        clamped.seconds
      end

      private

      sig { params(seconds: Integer).returns(Integer) }
      def clamp(seconds)
        [[seconds, MIN_INTERVAL.to_i].max, MAX_INTERVAL.to_i].min
      end

      sig { params(actor: ::User, reason: String, old_seconds: T.nilable(Integer), new_seconds: Integer).void }
      def log_update(actor:, reason:, old_seconds:, new_seconds:)
        GitHub.logger.info(
          "Copilot cache refresh interval updated via stafftools",
          "code.namespace" => "Copilot::CacheRefreshIntervalSetting",
          "gh.actor.id" => actor.id,
          "gh.actor.login" => actor.display_login,
          "gh.copilot.cache_refresh_interval.old_seconds" => old_seconds,
          "gh.copilot.cache_refresh_interval.new_seconds" => new_seconds,
          "gh.copilot.cache_refresh_interval.reason" => reason,
        )
      end

      sig { params(error: T.nilable(Exception)).void }
      def log_kv_unavailable(error)
        GitHub.logger.warn(
          "Copilot KV unavailable for cache refresh interval, using default",
          "code.namespace" => "Copilot::CacheRefreshIntervalSetting",
          "error" => error&.message,
        )
      end
    end
  end
end
