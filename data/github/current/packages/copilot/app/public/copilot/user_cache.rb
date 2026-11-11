# typed: strict
# frozen_string_literal: true

require "zstd-ruby"

module Copilot
  class UserCache
    include Kernel
    include Scientist
    include GitHub::Memoizer
    extend T::Helpers

    sig { returns(T::Array[::User]) }
    attr_reader :users

    sig { params(user: T.any(::User, T::Array[::User])).void }
    def initialize(user:)
      @users = T.let(Array(user).uniq, T::Array[::User])
    end

    sig { returns(::User) }
    def user
      T.must(users.first)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read
      if should_use_redis?
        read_from_redis
      else
        read_from_mysql
      end
    end

    sig { params(data: T::Hash[Symbol, T.untyped], throttle: T::Boolean).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def write(data, throttle: false)
      if should_use_redis?
        write_to_redis(data: data)
      else
        write_to_mysql(data: data, throttle: throttle)
      end
    end

    sig { params(reason: String).void }
    def invalidate(reason:)
      return if users.empty?

      if users.one?
        unless should_use_redis?
          # We didn't add support for mysql invalidation since it's only available in Proxima and being phased out.
          # We can still rely on the cache 12h TTL.
          # Additionally, existing code already rebuilds the cache using `create_copilot_settings_cache`.
          return
        end

        invalidate_in_redis(reason: reason)
        return
      end

      redis_users = users.select { |cache_user| should_use_redis_for_user?(cache_user) }

      return if redis_users.empty?

      emit_remote_cache_unavailable_metric(path: "invalidate")
      Copilot::Cache::PoliciesClient.new(user: redis_users).invalidate(reason)
      GitHub.dogstats.increment("copilot.user_cache.invalidated", tags: ["reason:#{reason}"], by: redis_users.size)
    end

    private

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read_from_redis
      GitHub.dogstats.increment("copilot.user_cache.read_from_redis")
      emit_remote_cache_unavailable_metric(path: "read")

      client = Copilot::Cache::PoliciesClient.new(user: user)
      client.fetch(graceful_degradation: true) do
        # This block is only called on cache miss or during extended telemetry.
        copilot_user.compute_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version)
          .merge({ source: "redis" })
          .deep_symbolize_keys
      end
    end

    sig { returns(Copilot::User) }
    memoize def copilot_user
      Copilot::User.new(user)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read_from_mysql
      GitHub.dogstats.increment("copilot.user_cache.read_from_mysql")

      ActiveRecord::Base.connected_to(role: :reading) do
        data = user.settings.get(:copilot_policy_data)

        return {} if data.blank?
        JSON.parse(data).deep_symbolize_keys
      rescue RuntimeError, JSON::ParserError => error
        Copilot::ErrorReporter.report!(error)
        {}
      end
    end

    sig { params(data: T::Hash[T.untyped, T.untyped], throttle: T::Boolean).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def write_to_mysql(data: {}, throttle: false)
      GitHub.dogstats.increment("copilot.user_cache.write_to_mysql")

      json = data.to_json

      with_write_type(throttle: throttle) do
        user.settings.set_without_reload!(:copilot_policy_data, json)
      end

      true
    rescue ActiveRecord::RecordNotUnique => error
      # Don't raise error as it was leading to sentry rate limiting. Log error instead.
      GitHub.logger.error("Failed to cache copilot settings for user due to database error", {
        "gh.user.id" => user.id,
        "error" => error.message,
        "error.class" => error.class.name,
      })

      false
    rescue StandardError => error
      Copilot::ErrorReporter.report!(error) # Send to dotcom-copilot sentry so doesn't get lost
      Kernel.raise error
    end

    sig { params(throttle: T::Boolean, block: T.proc.void).void }
    def with_write_type(throttle: false, &block)
      return ::User.throttle_writes(&block) if throttle

      ActiveRecord::Base.connected_to(role: :writing, &block)
    end

    sig { params(data: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def write_to_redis(data: {})
      GitHub.dogstats.increment("copilot.user_cache.write_to_redis")
      emit_remote_cache_unavailable_metric(path: "write")

      client = Copilot::Cache::PoliciesClient.new(user: user)
      client.store(data.merge({ source: "redis" }))

      # true if a remote/persistent cache store is available, false otherwise
      Copilot::Cache.client.remote_store_configured?
    end

    sig { params(reason: String).void }
    def invalidate_in_redis(reason:)
      emit_remote_cache_unavailable_metric(path: "invalidate")

      client = Copilot::Cache::PoliciesClient.new(user: user)
      client.invalidate(reason)

      GitHub.dogstats.increment("copilot.user_cache.invalidated", tags: ["reason:#{reason}"])
    end

    sig { params(path: String).void }
    def emit_remote_cache_unavailable_metric(path:)
      return if GH.context.remote_cache_override == GitHub::RemoteCacheOverride::Skip
      return if Copilot::Cache.client.remote_store_configured?

      tags = ["path:#{path}", GitHub::TaggingHelper.stamp_tag, GitHub::TaggingHelper.site_tag]
      tags.concat(GitHub.context[:remote_call_source_datadog_tags]) if GitHub.context[:remote_call_source_datadog_tags]

      GitHub.dogstats.increment(
        "copilot.user_cache.remote_cache_unavailable",
        tags: tags,
      )
    end

    sig { params(cache_user: ::User).returns(T::Boolean) }
    def should_use_redis_for_user?(cache_user)
      # When to use Redis:
      # 1. On dotcom, always use Redis.
      # 2. On GHES/Proxima, use Redis if the feature flag is enabled for the user.
      (GitHub.runtime.dotcom? && !GitHub.multi_tenant_enterprise?) || cache_user.feature_flag_enabled?(:copilot_settings_from_redis, default: false)
    end

    sig { returns(T::Boolean) }
    def should_use_redis?
      should_use_redis_for_user?(user)
    end
  end
end
