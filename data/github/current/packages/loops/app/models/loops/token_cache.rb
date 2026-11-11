# typed: strict
# frozen_string_literal: true

# Provides session-scoped caching for Loops tokens with SSO organization isolation.
#
# This class handles:
# - Session-scoped cache keys using UserSession.hashed_key
# - SSO organization isolation to prevent cross-org token reuse
# - Automatic TTL management (default 1 hour)
# - Cache invalidation on SSO organization changes
# - Token validation and refresh logic
class Loops::TokenCache
  include LoopsHelper

  DEFAULT_TTL = T.let(30.minutes, Integer)
  CACHE_VERSION = T.let("v1", String)
  CACHE_PREFIX = T.let("loops_token", String)

  sig { params(user_session: UserSession, saml_for_user: Platform::Authorization::SAML).void }
  def initialize(user_session, saml_for_user)
    @user_session = T.let(user_session, UserSession)
    @session_key = T.let(user_session.hashed_key, String)
    @saml_for_user = T.let(saml_for_user, Platform::Authorization::SAML)
  end

  # Getter for user_session (used in tests)
  sig { returns(UserSession) }
  attr_reader :user_session

  # Getter for session_key
  sig { returns(String) }
  attr_reader :session_key

  # Get cached token or create new one using the loops helper
  #
  # @param ttl [Integer] Time-to-live in seconds (default: DEFAULT_TTL)
  # @return [String, nil] The cached or newly created token
  sig { params(ttl: Integer).returns(T.nilable(String)) }
  def get_or_create_token(ttl: DEFAULT_TTL)
    sso_org_hash = calculate_sso_org_hash
    cache_key = generate_cache_key(sso_org_hash)

    cached_data = GitHub.cache.get(cache_key)

    if cached_data && token_still_valid?(cached_data[:expires_at])
      GitHub.dogstats.increment("loops.token_cache.hit")
      return cached_data[:token]
    end

    GitHub.dogstats.increment("loops.token_cache.miss")
    encrypted_token = loops_mint_token(@user_session, entry_point: :loops_token_cache)

    token_data = {
      token: encrypted_token.value,
      expires_at: encrypted_token.expiration
    }

    GitHub.cache.set(cache_key, token_data, ttl)
    encrypted_token.value
  end

  # Get cached token without creating a new one
  #
  # @return [String, nil] The cached token or nil if not found/expired
  sig { returns(T.nilable(String)) }
  def get_token
    sso_org_hash = calculate_sso_org_hash
    cache_key = generate_cache_key(sso_org_hash)
    cached_data = GitHub.cache.get(cache_key)

    return nil unless cached_data && token_still_valid?(cached_data[:expires_at])

    cached_data[:token]
  end

  # Store token in cache with TTL
  #
  # @param token [String, nil] The token to cache (nil allowed for marking invalid state)
  # @param expires_at [Time, nil] The expiration time for the token
  # @param ttl [Integer] Time-to-live in seconds (default: DEFAULT_TTL)
  # @return [Boolean] True if successfully cached
  sig { params(token: T.nilable(String), expires_at: T.nilable(Time), ttl: Integer).returns(T::Boolean) }
  def set_token(token, expires_at: nil, ttl: DEFAULT_TTL)
    sso_org_hash = calculate_sso_org_hash
    cache_key = generate_cache_key(sso_org_hash)

    token_data = {
      token: token,
      expires_at: expires_at
    }

    GitHub.cache.set(cache_key, token_data, ttl)
    true
  rescue => e
    Rails.logger.error("Failed to set Loops token cache: #{e.message}")
    false
  end

  # Invalidate cached token for current SSO organization context
  #
  # @return [Boolean] True if key was deleted
  sig { returns(T::Boolean) }
  def invalidate_token
    sso_org_hash = calculate_sso_org_hash
    cache_key = generate_cache_key(sso_org_hash)
    deleted_value = GitHub.cache.delete(cache_key)
    !deleted_value.nil?
  end

  # Check if a token exists in cache for the current SSO organization context
  #
  # @return [Boolean] True if valid token exists in cache
  sig { returns(T::Boolean) }
  def token_cached?
    sso_org_hash = calculate_sso_org_hash
    cache_key = generate_cache_key(sso_org_hash)
    cached_data = GitHub.cache.get(cache_key)

    !!(cached_data.present? && token_still_valid?(cached_data[:expires_at]))
  end

  private

  # Check if a token is still valid based on its expiration time
  #
  # @param expires_at [Time, nil] The expiration time of the token
  # @return [Boolean] True if token is still valid
  sig { params(expires_at: T.nilable(Time)).returns(T::Boolean) }
  def token_still_valid?(expires_at)
    return false unless expires_at

    # Use a 10 second buffer to avoid using tokens that expire very soon
    buffer = 10.seconds
    expires_at > (Time.current + buffer)
  end

  # Calculate SSO organization hash based on SAML protected organizations
  #
  # This creates a deterministic hash of the user's current SSO organization
  # context to isolate tokens by SSO state. Uses the provided SAML authorization
  # object passed from the client.
  #
  # @return [String] Hash of SSO-protected organization IDs
  sig { returns(String) }
  def calculate_sso_org_hash
    protected_org_ids = @saml_for_user.protected_organization_ids

    # Create a deterministic hash of the protected organization context
    org_context = protected_org_ids.empty? ? "default" : protected_org_ids.sort.join(",")
    T.must(Digest::SHA256.hexdigest(org_context)[0, 16]) # Use first 16 chars for brevity
  end

  # Generate cache key for session and SSO organization combination
  #
  # Format: "loops_token:v1:session:{hashed_key}:sso:{sso_org_hash}"
  #
  # @param sso_org_hash [String] Hash of SSO organization data
  # @return [String] The complete cache key
  sig { params(sso_org_hash: String).returns(String) }
  def generate_cache_key(sso_org_hash)
    "#{CACHE_PREFIX}:#{CACHE_VERSION}:session:#{@session_key}:sso:#{sso_org_hash}"
  end

end
