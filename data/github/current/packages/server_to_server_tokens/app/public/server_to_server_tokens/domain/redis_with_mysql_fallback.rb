# typed: strict
# frozen_string_literal: true

module ServerToServerTokens
  class Domain < GH::Domain::Base
    # Public methods for the Redis-first token lifecycle with MySQL fallback.
    #
    # Each method mirrors a MySQL-first counterpart on Domain (e.g.
    # create_redis_with_mysql_fallback / create) and is selected at the
    # callsite via redis_with_mysql_fallback?.
    module RedisWithMysqlFallback
      extend T::Helpers

      requires_ancestor { Domain }

      # Public: Check whether the given actors have been opted into the
      # Redis-with-MySQL-fallback token lifecycle via the
      # :dotcom_s2s_tokens_redis_with_mysql_fallback feature flag.
      #
      # actors - An Array of feature-flag actors (e.g. Integration instances).
      #          Nil entries are compacted before evaluation.
      #
      # Returns true when Redis is enabled and the flag is on for any actor.
      sig { params(actors: T::Array[T.untyped]).returns(T::Boolean) }
      def redis_with_mysql_fallback?(actors)
        actors.compact!

        return false if actors.empty?
        return false unless redis_enabled?

        FeatureFlag.vexi.enabled?(:dotcom_s2s_tokens_redis_with_mysql_fallback, actors, default: false)
      end

      # Public: Create an Authentication Token in Redis, falling back to a
      # MySQL-only create if Redis raises a connection error.
      #
      # authenticatable_id   - The Integer ID of the authenticatable record.
      # authenticatable_type - The String class name of the authenticatable.
      # span_attributes      - A Hash of String => String tracing attributes.
      # code_path            - An optional String code path for audit purposes.
      #
      # Returns a GH::Result[CreateResult] wrapping the token record and value.
      sig do
        params(
          authenticatable_id: Integer,
          authenticatable_type: String,
          span_attributes: T::Hash[String, String],
          code_path: T.nilable(String),
        ).returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise)
      end
      def create_redis_with_mysql_fallback(authenticatable_id, authenticatable_type, span_attributes, code_path: nil)
        record, token = RedisAuthenticationToken.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)

        GH::Result::Ok.new(CreateResult.new(record, token))
      rescue Redis::BaseError => e
        Failbot.report!(e)

        # If we have exhausted Redis retries, persist a token in MySQL with potential redis dual writes.
        create_mysql_only(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)
      end

      # Public: Extend the TTL of an authentication token. Attempts to extend
      # in Redis first; falls back to MySQL only when the token is not found
      # in Redis (e.g. the original create fell back to MySQL). All other
      # errors (validation, Redis connection) are returned directly.
      #
      # hashed_value - The String SHA-256 hashed token value.
      # expires_at   - A nilable String ISO 8601 timestamp for the new expiry.
      # entry_point  - An optional Symbol identifying the original caller.
      #
      # Returns a GH::Result[IAuthenticationToken] with the updated record.
      sig do
        params(
          hashed_value: String,
          expires_at: T.nilable(String),
          entry_point: T.nilable(Symbol),
        ).returns(GH::Result[IAuthenticationToken])
          .checked(:always).on_failure(:raise)
      end
      def extend_expires_at_redis_with_mysql_fallback(hashed_value, expires_at, entry_point: nil)
        return extend_expires_at_mysql_only(hashed_value, expires_at, entry_point:) unless redis_enabled?

        result = extend_expires_at_redis_only(hashed_value, expires_at, entry_point:)
        return result if result.ok?

        # Bubble up all other errors except if we "miss"
        return result unless result.is_a?(GH::Result::Error::NotFound)

        # If we have failed to find the token in Redis, we should attempt
        # again in MySQL in case the original creation failed.
        extend_expires_at_mysql_only(hashed_value, expires_at, entry_point:)
      end

      # Public: Destroy an authentication token by its hashed value. Attempts
      # to delete from Redis first. On success, also deletes the MySQL record
      # to prevent stale reads that fall back to MySQL from resurrecting a
      # revoked token. When the token is not found in Redis, falls back to
      # MySQL in case the original create fell back there.
      #
      # token - The String SHA-256 hashed token value.
      #
      # Returns a GH::Result[Boolean] — Ok(true) on success, Error::NotFound
      #   when the token exists in neither store.
      sig do
        params(token: String)
          .returns(GH::Result[T::Boolean])
          .checked(:always).on_failure(:raise)
      end
      def destroy_by_hashed_token_redis_with_mysql_fallback(token)
        return destroy_by_hashed_token_mysql_only(token) unless redis_enabled?

        result = destroy_by_hashed_token_redis_only(token)

        if result.ok?
          # Redis destroy succeeded — also cleanup MySQL so stale reads
          # don't resurrect the token.
          destroy_by_hashed_token_mysql_only(token)
          return result
        end

        # Token wasn't in Redis — try MySQL in case the original create
        # fell back to MySQL due to a Redis failure.
        if result.is_a?(GH::Result::Error::NotFound)
          return destroy_by_hashed_token_mysql_only(token)
        end

        result
      end

      # Public: Destroy a token from Redis by its hashed value. Emits
      # Datadog metrics for the outcome and reports connection errors to
      # Failbot.
      #
      # token - The String SHA-256 hashed token value.
      #
      # Returns GH::Result::Ok(true) on success, GH::Result::Error::NotFound
      #   when the key does not exist, or GH::Result::Error on Redis failure.
      sig do
        params(token: String)
          .returns(GH::Result[T::Boolean])
          .checked(:always).on_failure(:raise)
      end
      def destroy_by_hashed_token_redis_only(token)
        deleted = ServerToServerToken::Redis.del([
          RedisAuthenticationToken.key_for_hashed_value(token)
        ])

        result_status = deleted == 0 ? "not_found" : "success"

        GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:destroy", "result:#{result_status}"])
        return GH::Result::Error::NotFound.new if deleted == 0

        GH::Result::Ok.new(true)
      rescue Redis::BaseError => e
        GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:destroy", "result:failure"])
        Failbot.report!(e)

        GH::Result::Error.new(e.message)
      end

      private

      # Internal: Create a token in MySQL only (no Redis). Used as the
      # fallback path when Redis is unavailable.
      #
      # authenticatable_id   - The Integer ID of the authenticatable record.
      # authenticatable_type - The String class name of the authenticatable.
      # span_attributes      - A Hash of String => String tracing attributes.
      # code_path            - An optional String code path for audit purposes.
      #
      # Returns a GH::Result[CreateResult].
      sig do
        params(
          authenticatable_id: Integer,
          authenticatable_type: String,
          span_attributes: T::Hash[String, String],
          code_path: T.nilable(String),
        ).returns(GH::Result[CreateResult])
      end
      def create_mysql_only(authenticatable_id, authenticatable_type, span_attributes, code_path: nil)
        record, token = AuthenticationToken.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)

        GH::Result::Ok.new(CreateResult.new(record, token))
      end

      # Internal: Destroy a token from MySQL by its hashed value.
      #
      # token - The String SHA-256 hashed token value.
      #
      # Returns GH::Result::Ok(true) on success, GH::Result::Error::NotFound
      #   when no active token matches.
      sig do
        params(token: String)
          .returns(GH::Result[T::Boolean])
          .checked(:always).on_failure(:raise)
      end
      def destroy_by_hashed_token_mysql_only(token)
        record = ::AuthenticationToken.active.find_by(hashed_value: token)
        return GH::Result::Error::NotFound.new unless record

        record.destroy
        GH::Result::Ok.new(true)
      end

      # Internal: Extend the TTL of a token in MySQL only.
      #
      # hashed_value - The String SHA-256 hashed token value.
      # expires_at   - A nilable String ISO 8601 timestamp for the new expiry.
      # entry_point  - An optional Symbol identifying the original caller.
      #
      # Returns a GH::Result[IAuthenticationToken] with the updated record,
      #   or GH::Result::Error when validation fails.
      sig do
        params(
          hashed_value: String,
          expires_at: T.nilable(String),
          entry_point: T.nilable(Symbol),
        ).returns(GH::Result[IAuthenticationToken])
          .checked(:always).on_failure(:raise)
      end
      def extend_expires_at_mysql_only(hashed_value, expires_at, entry_point: nil)
        record = ::AuthenticationToken.find_by(hashed_value: hashed_value)

        return GH::Result::Error::NotFound.new unless record
        result = AuthenticationToken.extend_expires_at(record, expires_at, entry_point: entry_point)

        return GH::Result::Ok.new(record) if result.success?
        GH::Result::Error.new(result.message)
      end

      # Internal: Extend the TTL of a token in Redis only. Reads the token
      # from Redis, validates and applies the new expiry, and reports
      # connection errors to Failbot.
      #
      # hashed_value - The String SHA-256 hashed token value.
      # expires_at   - A nilable String ISO 8601 timestamp for the new expiry.
      # entry_point  - An optional Symbol identifying the original caller.
      #
      # Returns a GH::Result[IAuthenticationToken] with the updated record,
      #   GH::Result::Error::NotFound when the token is not in Redis, or
      #   GH::Result::Error on validation / connection failure.
      sig do
        params(
          hashed_value: String,
          expires_at: T.nilable(String),
          entry_point: T.nilable(Symbol),
        ).returns(GH::Result[IAuthenticationToken])
          .checked(:always).on_failure(:raise)
      end
      def extend_expires_at_redis_only(hashed_value, expires_at, entry_point: nil)
        result = read_from_redis(hashed_value)
        return GH::Result::Error::NotFound.new unless result.ok?

        record = T.must(result.ok)

        result = RedisAuthenticationToken.extend_expires_at(record, expires_at, entry_point: entry_point)
        return GH::Result::Error.new(result.message) unless result.success?

        GH::Result::Ok.new(record)
      rescue Redis::BaseError => e
        Failbot.report!(e)
        GH::Result::Error.new(e.message, e)
      end
    end
  end
end
