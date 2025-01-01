# typed: true
# frozen_string_literal: true

# Provides a fingerprint identifying the actor originating a request based on
# authorization information (if any) and the remote IP.
class Api::RequestAuthenticationFingerprint

  class Actor
    attr_reader :fingerprint, :limit_multiplier, :type

    def initialize(fingerprint:, limit_multiplier: 1, type: :other)
      @fingerprint = fingerprint
      @limit_multiplier = limit_multiplier
      @type = type
    end
  end

  DELIMITER  = ":".freeze
  TOKEN_KEYS = %w(bearer_token access_token oauth_token)
  INVALID_USERNAME_PLACEHOLDER = "@invalid".freeze

  VALID_SERIALIZATIONS = %i[default hashed_token].freeze

  attr_reader :authorization
  attr_reader :request

  def initialize(env, token_serialization: :default, omit_ip: false)
    raise "Invalid serialization format for token: '#{token_serialization}'" unless VALID_SERIALIZATIONS.include?(token_serialization)

    @authorization       = Rack::Auth::Basic::Request.new(env)
    @request             = Rack::Request.new(env)
    @token_serialization = token_serialization
    @omit_ip             = omit_ip
  end

  def self.from(env, token_serialization: :default, omit_ip: false)
    new(env, token_serialization: token_serialization, omit_ip: omit_ip)
  end

  def actor
    @actor ||= detect_actor
  end

  def limit_multiplier
    actor.limit_multiplier
  end

  def to_s
    actor.fingerprint
  end

  def auth_type
    actor.type
  end

  def personal_access_token?
    rtoken = raw_token
    valid_token?(rtoken) && GitHub.auth.authnd_token?(rtoken)
  end

  private

  # Internal: Determine an actor from an HTTP request, checking each
  # form of authorization we support, falling back to the remote IP if no
  # authorization info is available.
  #
  # Returns a String.
  def detect_actor
    token || app || user || integration || hmac || psi || fallback
  end

  def hmac
    # Internal: Return an actor for any request using an hmac token
    # with a fingerprint in the format of `hmac:<last 8 chars of token>:<ip>`.
    token = request.env["HTTP_REQUEST_HMAC"]

    unless token.blank?
      Actor.new(fingerprint: build("hmac", token.last(8), request_ip))
    end
  end

  # Proxima Service Identity
  #
  # Proxima service identities are GitHub owned internal services
  # that send unauthenticated requests from Proxima stamps to dotcom
  # on behalf of tenants.
  #
  # Internal: Return an actor for any request using a proxima service token (jwt)
  # with a fingerprint in the format of `psi:<last 8 chars of token>:<ip>`.
  #
  # Returns an Actor or nil if the request is not using a proxima service token.
  def psi
    return unless GitHub.flipper[:proxima_service_rate_limits_secondary].enabled?

    psi_token = request.env["HTTP_X_GITHUB_PSI_JWT"]

    unless psi_token.blank?
      Actor.new(fingerprint: build("psi", psi_token.last(8), request_ip))
    end
  end

  # Internal: Return an actor for any request using an access token
  # with a fingerprint in the format of determined by token_serialization:
  # - default      = `token:<last 8 chars of token>:<ip>`
  # - hashed_token = `token:<sha256 hash of token>`
  #
  # Returns an Actor or nil if the request is not using a token.
  def token
    rtoken = raw_token
    return unless valid_token?(rtoken)

    fingerprint = case @token_serialization
    when :default
      build("token", rtoken.last(8), request_ip)
    when :hashed_token
      build("token", ProgrammaticAccessToken.hash_token(rtoken))
    end

    Actor.new(fingerprint: fingerprint)
  end

  # Internal: Returns the plaintext token as a string.
  #
  # Returns a String or nil if the request is not using a token
  def raw_token
    token = if authorization_valid?(authorization)
      auth_username = authorization.username.to_s

      if authorization.basic? && valid_token?(auth_username)
        auth_username
      elsif authorization.basic? &&
        valid_token?(authorization.credentials[1]) &&
        !oauth_app_credentials_valid?(authorization.credentials)
        authorization.credentials[1]
      else
        authorization.params
      end
    else
      request.GET.slice(*TOKEN_KEYS).values.compact.first
    end
    token.to_s
  end

  def valid_token?(token)
    return false unless token.is_a?(String)

    token.valid_encoding? && GitHub.auth.access_token?(token)
  end

  # Internal: Return an actor for any request using client_id and client_secret
  # with a fingerprint in the format of `app:<client_id>:<remote ip>`.
  #
  # Returns an Actor or nil if the request is not using application authentication.
  def app
    key = if authorization_valid?(authorization) && authorization.basic?
      if oauth_app_credentials_valid?(authorization.credentials)
        authorization.username
      end
    else
      request.GET["client_id"]
    end

    return unless key

    Actor.new(fingerprint: build("app", key, request_ip), type: :app)
  end

  # Internal: Return an actor for any rany user Basic Auth request
  # with a fingerprint in the format of `user:<login>:<remote ip>`.
  #
  # Returns an Actor or nil if the request is not using application authentication.
  def user
    if authorization_valid?(authorization) && authorization.basic?
      # This is *probably* a user logging in with basic auth via their login and password.
      # But, it could actually be a user logging in via OAuth and a personal access token as their
      # password.
      username = if User::LOGIN_REGEX =~ authorization.username
        authorization.username
      elsif User::LOGIN_REGEX_FOR_EMUS =~ authorization.username && GitHub.flipper[:emu_basic_auth_fingerprint].enabled?
        authorization.username
      end

      return unless username

      Actor.new(fingerprint: build("user", username, request_ip), type: :user)
    end
  end

  # Internal: Return a unique key for any GitHub App (Integration) JWT Auth request
  # in the format of `integration:<id>:<remote ip>`.
  #
  # Returns a string or nil if the request Authorization header is not using
  # the "Bearer" scheme and if the JWT is invalid.
  def integration
    if authorization_valid?(authorization) && authorization.scheme == "bearer"
      assertion = Api::IntegrationAssertion.new(request.env)
      if assertion.valid?
        Actor.new(
          fingerprint: build("integration", assertion.integration.id, request_ip),
          limit_multiplier: assertion.integration.abuse_limits_multiplier,
          type: :integration
        )
      end
    end
  end

  def fallback
    fingerprint = request_ip
    ja3_hash = request.env["HTTP_X_SSL_JA3_HASH"]
    fingerprint = [fingerprint, ja3_hash].compact.join(DELIMITER)

    Actor.new(fingerprint: fingerprint, type: :fallback)
  end

  def build(*parts)
    parts.reject(&:blank?).join(DELIMITER)
  end

  # Conditionally include IP in the fingerprint
  def request_ip
    @omit_ip ? nil : request.ip
  end

  # Internal: This method ensures that an auth header is valid before processing it.
  # It checks to see if a header exists, and it ensures that the value of that header
  # is non-nil.
  #
  # Returns a Boolean true/false.
  def authorization_valid?(authorization)
    # TODO: remove this if https://git.io/v2jQP ever merges and comes into GitHub
    authorization.provided? && authorization.params
  rescue NoMethodError
    false
  end

  def oauth_app_credentials_valid?(credentials)
    credentials &&
      credentials.compact.map(&:size) == [20, 40] &&
      OauthApplication.client_id?(credentials[0]) &&
      OauthApplicationClientSecret::SECRET_PATTERN =~ credentials[1]
  end
end
