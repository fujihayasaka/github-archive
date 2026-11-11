# typed: strict
# frozen_string_literal: true

module Copilot
  # Manages the minimum version for Copilot user policy cache validation.
  #
  # This class provides a dynamic mechanism to invalidate all user policy caches
  # without requiring a code deployment. The version is stored in the Copilot KV
  # store and can be bumped via stafftools.
  #
  # The minimum version is read from the KV store. If the KV store is unavailable,
  # we "fail open" by skipping the version check (returning 0), relying on the
  # TTL-based cache expiration instead.
  class PolicyCacheVersion
    CACHE_VERSION_KEY = "copilot:policy_cache:minimum_version"

    class << self
      # Returns the minimum version for cache validation.
      #
      # Caches with a version below this value are considered invalid and will
      # be rebuilt.
      sig { returns(Integer) }
      def minimum_version
        fetch_dynamic_version
      end

      # Returns the current version that gets written to new caches.
      sig { returns(Integer) }
      def current_version
        # Use the higher of minimum_version or the constant to ensure new caches
        # are always valid. The max() guards against KV unavailability, where
        # minimum_version returns 0 (fail open) - we still want caches written
        # with at least the code constant version.
        [minimum_version, Copilot::Public::User::CURRENT_VERSION].max
      end

      # Bumps the cache version to force all users to rebuild their policy cache.
      #
      # This should be used when a policy change requires immediate re-evaluation
      # of all user caches, without waiting for the normal 12-hour TTL expiration.
      sig { params(actor: ::User, reason: String).returns(Integer) }
      def bump!(actor:, reason:)
        current = fetch_dynamic_version
        new_version = current + 1
        Copilot::KV.store.set(CACHE_VERSION_KEY, new_version.to_s)

        log_bump(actor: actor, reason: reason, old_version: current, new_version: new_version)

        new_version
      end

      # Returns the raw stored version from KV (for display in stafftools).
      sig { returns(T.nilable(Integer)) }
      def stored_version
        result = Copilot::KV.store.get(CACHE_VERSION_KEY)
        return nil unless result.ok?

        value = result.value!
        return nil if value.nil? || value.empty?

        value.to_i
      end

      private

      sig { returns(Integer) }
      def fetch_dynamic_version
        result = Copilot::KV.store.get(CACHE_VERSION_KEY)

        if result.ok?
          stored_value = result.value!
          if stored_value.present?
            stored_value.to_i
          else
            # Key doesn't exist yet - return constant value
            # Seeding will happen on first bump! call (avoids write on read)
            Copilot::Public::User::MINIMUM_VERSION
          end
        else
          # KV unavailable - fail open by returning 0 (skip version check)
          # The TTL-based expiration will still work as a safety net
          log_kv_unavailable(result.error)
          0
        end
      end

      sig { params(actor: ::User, reason: String, old_version: Integer, new_version: Integer).void }
      def log_bump(actor:, reason:, old_version:, new_version:)
        GitHub.logger.info(
          "Copilot policy cache version bumped via stafftools",
          "code.namespace" => "Copilot::PolicyCacheVersion",
          "gh.actor.id" => actor.id,
          "gh.actor.login" => actor.display_login,
          "gh.copilot.policy_cache.old_version" => old_version,
          "gh.copilot.policy_cache.new_version" => new_version,
          "gh.copilot.policy_cache.reason" => reason,
        )
      end

      sig { params(error: T.nilable(Exception)).void }
      def log_kv_unavailable(error)
        GitHub.logger.warn(
          "Copilot KV unavailable for policy cache version, failing open",
          "code.namespace" => "Copilot::PolicyCacheVersion",
          "error" => error&.message,
        )
      end
    end
  end
end
