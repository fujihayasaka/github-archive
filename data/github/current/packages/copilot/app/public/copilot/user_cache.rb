# typed: strict
# frozen_string_literal: true

require "zstd-ruby"

module Copilot
  class UserCache
    include Kernel
    include Scientist
    include GitHub::Memoizer
    extend T::Helpers

    sig { returns(::User) }
    attr_reader :user

    sig { params(user: ::User).void }
    def initialize(user:)
      @user = user
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read
      return read_from_redis if user.feature_flag_enabled?(:copilot_settings_from_redis, default: false)
      read_from_mysql
    end

    sig { params(data: T::Hash[Symbol, T.untyped], throttle: T::Boolean).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def write(data, throttle: false)
      redis_data = data.merge({ source: "redis" })

      if user.feature_flag_enabled?(:stop_writing_copilot_settings_to_mysql, default: false) && !user.feature_flag_enabled?(:copilot_settings_from_redis, default: false)
        GitHub.logger.info("Skipping write for user copilot settings cache", "gh.user.id": user.id)
      end

      if user.feature_flag_enabled?(:stop_writing_copilot_settings_to_mysql, default: false)
        # This is phase 2 of rolling out to redis. At this point, we'll only be writing to redis and not mysql.

        return write_to_redis(data: redis_data) if user.feature_flag_enabled?(:copilot_settings_from_redis, default: false)
        false
      else
        # TODO: Delete this when we're done rolling out to redis completely.
        # This is phase 1 of rolling out to redis. At this point, we'll be writing to both mysql and redis. We do not
        # want to remove it until we've moved entirely to redis.

        # write_to_mysql needs to run last as it can raise an error, whereas write_to_redis does not
        write_to_redis(data: redis_data) if user.feature_flag_enabled?(:copilot_settings_from_redis, default: false)
        write_to_mysql(data: data, throttle: throttle)
      end
    end

    private

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read_from_redis
      GitHub.dogstats.increment("copilot.user_cache.read_from_redis")

      cache_miss = T.let(false, T::Boolean)
      client = Copilot::Cache::PoliciesClient.new(user: user)
      result = client.fetch(graceful_degradation: true) do
        # This block is only called on cache miss or during extended telemetry.
        cache_miss = true
        copilot_user = Copilot::User.new(user)
        copilot_user.compute_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version)
          .merge({ source: "redis" })
          .deep_symbolize_keys
      end

      # During phase 1, if Redis had a cache miss, also write to MySQL to keep it in sync.
      # - stop_writing_copilot_settings_to_mysql: skip if we've moved past phase 1 and no longer write to MySQL
      # - copilot_policies_cache_extended_telemetry: skip because extended telemetry runs the fetch block on
      #   every call (not just misses), which would cause excessive MySQL writes
      # - copilot_skip_write_cache_on_load: skip if cache writes on load are disabled
      # - copilot_skip_no_access_cache: skip when the user does not have Copilot access
      # - store_configured?: skip when Redis is unavailable (e.g. Proxima), since every read
      #   is a cache miss and writing to MySQL on every miss would be excessive
      should_write_to_mysql_on_cache_miss = cache_miss && result.present? &&
        !user.feature_flag_enabled?(:stop_writing_copilot_settings_to_mysql, default: false) &&
        !user.feature_flag_enabled?(:copilot_policies_cache_extended_telemetry, default: false) &&
        !user.feature_flag_enabled?(:copilot_skip_write_cache_on_load, default: false) &&
        Copilot::Cache.client.store_configured?

      if should_write_to_mysql_on_cache_miss &&
          !should_skip_mysql_write_for_no_access? &&
          !should_skip_mysql_write_for_freno?
        begin
          write_to_mysql(data: result.except(:source), throttle: !GitHub.foreground?)
        rescue StandardError
          # This write is best-effort to keep MySQL in sync. We swallow all errors to avoid
          # breaking the read path — the Redis result is already available and should be returned.
          # Note: write_to_mysql already reports errors to Sentry before re-raising, so we
          # intentionally do not report again here to avoid double-reporting.
        end
      end

      result
    end

    sig { returns(T::Boolean) }
    def should_skip_mysql_write_for_no_access?
      return false unless user.feature_flag_enabled?(:copilot_skip_no_access_cache, default: false)
      return false if copilot_user.has_copilot_access?

      GitHub.dogstats.increment("copilot.user_cache.skip_mysql_write_no_access")
      true
    end

    sig { returns(T::Boolean) }
    def should_skip_mysql_write_for_freno?
      return false unless GitHub.foreground?
      return false unless user.feature_flag_enabled?(:copilot_freno_check_settings_writes, default: false)
      return false if freno_ok_to_write?

      GitHub.dogstats.increment("copilot.settings_cache.freno_throttled", tags: ["store:mysql1", "path:redis_cache_miss_backfill"])
      true
    end

    MYSQL1_REPLICATION_DELAY_THRESHOLD = 1.0 # seconds

    sig { returns(T::Boolean) }
    def freno_ok_to_write?
      delay = Freno.client.replication_delay(app: :github, store_name: :mysql1)
      delay <= MYSQL1_REPLICATION_DELAY_THRESHOLD
    rescue Freno::Error
      GitHub.dogstats.increment("copilot.settings_cache.freno_check_error", tags: ["store:mysql1", "path:redis_cache_miss_backfill"])
      true
    end

    sig { returns(Copilot::User) }
    memoize def copilot_user
      Copilot::User.new(user)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def read_from_mysql
      GitHub.dogstats.increment("copilot.user_cache.read_from_mysql")

      ActiveRecord::Base.connected_to(role: :reading) do
        uncompressed_data = user.settings.get(:copilot_policy_data)
        compressed_data = user.settings.get(:copilot_policy_compressed_data)

        science "compressed_copilot_user_cache_read" do |e|
          e.run_if { user.feature_flag_enabled?(:compressed_copilot_user_cache_experiment, default: false) && compressed_data.present? }

          e.use do
            next {} if uncompressed_data.blank?
            JSON.parse(uncompressed_data).deep_symbolize_keys
          end

          e.try do
            next {} if compressed_data.blank?

            decoded_data = Base64.strict_decode64(compressed_data)

            unless decoded_data.bytes.first == 0x28
              error = StandardError.new("Expected compressed data but received uncompressed data")
              Copilot::ErrorReporter.report!(error)
              next {}
            end

            decompressed = Zstd.decompress(decoded_data)
            JSON.parse(decompressed).deep_symbolize_keys
          rescue RuntimeError, JSON::ParserError => error
            Copilot::ErrorReporter.report!(error)
            {}
          end
        end
      end
    end

    sig { params(data: T::Hash[T.untyped, T.untyped], throttle: T::Boolean).returns(T::Boolean) } # rubocop:disable Sorbet/ForbidTUntyped
    def write_to_mysql(data: {}, throttle: false)
      GitHub.dogstats.increment("copilot.user_cache.write_to_mysql")

      json = data.to_json
      GitHub.dogstats.distribution("copilot.user_settings_cache.data_size", json.bytesize, tags: ["type:uncompressed"])

      if user.feature_flag_enabled?(:compressed_copilot_user_cache_experiment, default: false)
        compressed_data = Base64.strict_encode64(Zstd.compress(json))
        GitHub.dogstats.distribution("copilot.user_settings_cache.data_size", compressed_data.bytesize, tags: ["type:compressed"])

        with_write_type(throttle: throttle) do
          user.settings.set_multiple_without_reload!(
            copilot_policy_data: json,
            copilot_policy_compressed_data: compressed_data,
          )
        end
      else
        with_write_type(throttle: throttle) do
          user.settings.set_without_reload!(:copilot_policy_data, json)
        end
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

      client = Copilot::Cache::PoliciesClient.new(user: user)
      client.store(data)

      true
    end
  end
end
