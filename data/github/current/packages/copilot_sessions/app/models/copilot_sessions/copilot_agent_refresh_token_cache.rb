# typed: strict
# frozen_string_literal: true

# Provides user-scoped caching for Copilot agent tokens (both access and refresh).
#
# This class stores tokens keyed by the user's ID, ensuring a single
# cached token set per user regardless of browser session. This approach:
# - Keeps refresh tokens server-side only (never exposed to client)
# - Ties token lifecycle to the user identity
# - Stores SSO org IDs to detect context changes (triggers refresh, not re-mint)
# - Uses GitHub.cache (Memcached/Redis) for storage
# - Automatically expires with TTL
#
# Usage:
#   cache = CopilotAgentRefreshTokenCache.new(user)
#   cache.set_tokens(access_token: token, expiration: exp, refresh_token: refresh, sso_org_ids: ids)
#   cached = cache.get_tokens  # returns { access_token:, expiration:, refresh_token:, sso_org_ids: }
#
module CopilotSessions
  class CopilotAgentRefreshTokenCache
    # TTL aligned to refresh token expiry (30 days)
    DEFAULT_TTL = T.let(30.days.to_i, Integer)
    # Buffer before access token expiration to trigger refresh (5 minutes)
    ACCESS_TOKEN_EXPIRY_BUFFER = T.let(5.minutes.to_i, Integer)
    CACHE_VERSION = T.let("v3", String)
    CACHE_PREFIX = T.let("copilot_agent_refresh_token", String)

    @cache_version = T.let(nil, T.nilable(String))
    @cache_key = T.let(nil, T.nilable(String))

    sig { params(user: User).void }
    def initialize(user)
      @user = T.let(user, User)
      @user_id = T.let(user.id, Integer)
      @cache_version = T.let(nil, T.nilable(String))
      @cache_key = T.let(nil, T.nilable(String))
    end

    # Getter for user (used in tests)
    sig { returns(User) }
    attr_reader :user

    # Getter for user_id
    sig { returns(Integer) }
    attr_reader :user_id

    # Get all cached tokens (access token, expiration, refresh token, and sso_org_ids)
    #
    # @return [Hash, nil] Hash with :access_token, :expiration, :refresh_token, :sso_org_ids or nil if not found
    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def get_tokens
      cached_data = GitHub.cache.get(cache_key)
      return nil unless cached_data.is_a?(Hash)

      {
        access_token: cached_data[:access_token],
        expiration: cached_data[:expiration],
        refresh_token: cached_data[:refresh_token],
        sso_org_ids: cached_data[:sso_org_ids] || []
      }
    end

    # Check if the cached token's SSO context matches the current user's SSO context
    #
    # @param current_sso_org_ids [Array<Integer>] The current user's SSO-protected org IDs
    # @return [Boolean] True if SSO context matches (or both are empty)
    sig { params(current_sso_org_ids: T::Array[Integer]).returns(T::Boolean) }
    def sso_context_matches?(current_sso_org_ids)
      cached_data = GitHub.cache.get(cache_key)
      return true unless cached_data.is_a?(Hash) # No cache = no mismatch

      cached_sso_org_ids = cached_data[:sso_org_ids] || []
      cached_sso_org_ids.sort == current_sso_org_ids.sort
    end

    # Check if cached access token is still valid (not expired with buffer)
    #
    # @return [Boolean] True if access token exists and is not near expiration
    sig { returns(T::Boolean) }
    def access_token_valid?
      cached_data = GitHub.cache.get(cache_key)
      return false unless cached_data.is_a?(Hash)
      return false unless cached_data[:access_token].present? && cached_data[:expiration].present?

      # Check if token expires within the buffer window
      expiration = cached_data[:expiration]
      Time.now < (expiration - ACCESS_TOKEN_EXPIRY_BUFFER)
    end

    # Get cached refresh token (legacy method for backwards compatibility)
    #
    # @return [String, nil] The cached refresh token or nil if not found
    sig { returns(T.nilable(String)) }
    def get_refresh_token
      cached_data = GitHub.cache.get(cache_key)
      return nil unless cached_data.is_a?(Hash)

      cached_data[:refresh_token]
    end

    # Store all tokens in cache with TTL
    #
    # @param access_token [String] The encrypted access token to cache
    # @param expiration [Time] When the access token expires
    # @param refresh_token [String] The encrypted refresh token to cache
    # @param sso_org_ids [Array<Integer>] The SSO org IDs for this token context
    # @param ttl [Integer] Time-to-live in seconds (default: DEFAULT_TTL)
    # @return [Boolean] True if successfully cached
    sig { params(access_token: String, expiration: Time, refresh_token: String, sso_org_ids: T::Array[Integer], ttl: Integer).returns(T::Boolean) }
    def set_tokens(access_token:, expiration:, refresh_token:, sso_org_ids: [], ttl: DEFAULT_TTL)
      token_data = {
        access_token: access_token,
        expiration: expiration,
        refresh_token: refresh_token,
        sso_org_ids: sso_org_ids,
        cached_at: Time.current
      }

      all_caches.each { |cache| cache.set(cache_key, token_data, ttl) }
      true
    rescue => e
      Rails.logger.error("Failed to set Copilot agent token cache: #{e.message}")
      false
    end

    # Store refresh token in cache with TTL (legacy method for backwards compatibility)
    #
    # @param refresh_token [String] The refresh token to cache
    # @param ttl [Integer] Time-to-live in seconds (default: DEFAULT_TTL)
    # @return [Boolean] True if successfully cached
    sig { params(refresh_token: String, ttl: Integer).returns(T::Boolean) }
    def set_refresh_token(refresh_token, ttl: DEFAULT_TTL)
      # Preserve existing access token if present
      cached_data = GitHub.cache.get(cache_key)
      token_data = if cached_data.is_a?(Hash)
        cached_data.merge(refresh_token: refresh_token, cached_at: Time.current)
      else
        { refresh_token: refresh_token, cached_at: Time.current }
      end

      all_caches.each { |cache| cache.set(cache_key, token_data, ttl) }
      true
    rescue => e
      Rails.logger.error("Failed to set Copilot agent refresh token cache: #{e.message}")
      false
    end

    # Invalidate cached refresh token for current session
    #
    # @return [Boolean] True if key was deleted from at least one cache
    sig { returns(T::Boolean) }
    def invalidate
      deleted = T.let(false, T::Boolean)
      all_caches.each do |cache|
        result = cache.delete(cache_key)
        deleted = true if result
      end
      deleted
    rescue => e
      Rails.logger.error("Failed to invalidate Copilot agent refresh token cache: #{e.message}")
      false
    end

    # Check if a refresh token exists in cache
    #
    # @return [Boolean] True if token exists in cache
    sig { returns(T::Boolean) }
    def token_cached?
      cached_data = GitHub.cache.get(cache_key)
      cached_data.is_a?(Hash) && cached_data[:refresh_token].present?
    end

    private

    # Returns all caches (local + regional) for cross-DC writes
    # This ensures tokens are consistent across all datacenters
    #
    # @return [Array] All cache instances (may include DualClient, Redis-backed stores, etc.)
    sig { returns(T::Array[T.untyped]) }
    def all_caches
      [GitHub.cache, *GitHub.regional_caches.values]
    end

    # Determine the cache version based on feature flag
    #
    # @return [String] "v4" if copilot_agent_token_cache_v4 is enabled for the user, otherwise "v3"
    sig { returns(String) }
    def cache_version
      @cache_version ||= if FeatureFlag.vexi.enabled?(:copilot_agent_token_cache_v4, @user, default: false)
        "v4"
      else
        CACHE_VERSION
      end
    end

    # Generate cache key for user
    #
    # Format: "copilot_agent_refresh_token:{version}:user:{user_id}"
    #
    # @return [String] The complete cache key
    sig { returns(String) }
    def cache_key
      @cache_key ||= "#{CACHE_PREFIX}:#{cache_version}:user:#{@user_id}"
    end
  end
end
