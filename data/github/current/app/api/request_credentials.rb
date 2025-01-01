# typed: true
# frozen_string_literal: true

# Fetches the authentication credentials for a for a given API request.
class Api::RequestCredentials
  # "OAuth2 spec is crazy, yo." -- Risk Olson (Apr 13, 2011)
  TOKEN_PARAMS = %w(bearer_token access_token oauth_token).freeze
  AUTHORIZATION_SCHEMES = %w(bearer oauth2 token).freeze
  OTP_KEY              = "HTTP_X_GITHUB_OTP"
  OAUTH_BASIC_PASSWORD = /^(x-oauth-basic)?$/
  PROXIMA_SERVICE_TOKEN_HEADER = "HTTP_X_GITHUB_PSI_JWT"

  # Internal Exchange Tokens are JWTs issued by authnd in exchange for a
  # user-facing access token (e.g. PAT, oauth access, or s2s). Currently,
  # they are not fully fledged credentials in gh/gh and are used purely
  # for Science Experiments, when present.
  INTERNAL_EXCHANGE_TOKEN_HEADER = "HTTP_X_GITHUB_IET"

  include App::IRequestCredentials

  attr_accessor :login, :password, :otp, :token, :via_params, :proxima_service_token, :internal_exchange_token

  # Public: fetch an authentication token from a Rack env based on known
  # Authorization fields. These fields are HTTP_AUTHORIZATION,
  # X-HTTP_AUTHORIZATION, and X_HTTP_AUTHORIZATION.
  #
  # Note - If you use this method for fetching a basic auth scheme, the return
  # value will be a single base64 value. To fetch the individual
  # username/password values use
  # `Api::RequestCredentials.login_password_from_basic(env)`.
  #
  # env    - The Rack environment from which to extract the token.
  # scheme - The scheme to look for in the authorization header.
  #
  # Returns a token if one is found with an appropriate scheme and nil
  # otherwise.
  def self.token_from_scheme(env, scheme)
    auth = Rack::Auth::Basic::Request.new(env)
    return nil unless auth.provided?
    if auth.scheme != scheme || auth.parts.size != 2
      return nil
    end

    auth.params
  end

  # Public: fetch basic auth credentials from Rack env based on known
  # Authorization fields. These fields are HTTP_AUTHORIZATION,
  # X-HTTP_AUTHORIZATION, and X_HTTP_AUTHORIZATION.
  #
  # env - The Rack environment from which to extract the basic credentials.
  #
  # Returns an Array of [username, password] if an authorization header with
  # basic auth credentials are found and an array of nil values otherwise.
  def self.login_password_from_basic(env)
    auth = Rack::Auth::Basic::Request.new(env)
    return [nil, nil] unless auth.provided? && auth.basic?

    auth.credentials
  end

  # Extract authentication information for an API request from from request
  # headers and query parameters.
  #
  # env     - The Rack environment from which to extract the API
  #           credentials.
  # headers - Whether to look for credentials in Authorization header
  # params  - Whether to look for oauth tokens in query paramters.
  #
  # Returns a RequestCredentials instance, populated with login, password, otp,
  # and token that were found in the request enviorment and are appropriate for
  # authenticating to the GitHub API.
  def self.from_env(env, headers: true, params: true)
    request = Rack::Request.new(env)
    auth = Rack::Auth::Basic::Request.new(env)
    creds = new
    if headers && auth.provided? && (auth.scheme == "basic")
      login, password = auth.credentials
      creds.login = login.to_s
      creds.password = password.to_s
      creds.otp = request.env[OTP_KEY].to_s
    elsif headers && auth.provided? && AUTHORIZATION_SCHEMES.include?(auth.scheme)
      creds.set_token(auth.params.to_s)
    elsif params
      # We didn't find a token in an authorization header, so look for it in a
      # query param.
      params_key = TOKEN_PARAMS.detect { |key| request.params.has_key?(key) }
      if params_key
        # Just in case a bogus type is sent, we cast it to a String so that
        # subsequent processing can fail cleanly.
        creds.set_token(request.params[params_key].to_s)
        creds.via_params = true if creds.token_present?
        GitHub.dogstats.increment("api.access_token_credentials_via_query_params", tags: ["key:#{params_key}"])
      end
    end
    creds.initialize_token_from_login_or_password

    if request.env[INTERNAL_EXCHANGE_TOKEN_HEADER].present? && GitHub.flipper[:internal_exchange_tokens].enabled?
      GitHub.dogstats.increment("api.internal_exchange_token.received")
      creds.internal_exchange_token = request.env[INTERNAL_EXCHANGE_TOKEN_HEADER].to_s
    end

    if !creds.credentials_present? && request.env[PROXIMA_SERVICE_TOKEN_HEADER].present? && GitHub.flipper[:proxima_service_rate_limits].enabled?
      GitHub.dogstats.increment("api.proxima_service_token.received")
      creds.proxima_service_token = request.env[PROXIMA_SERVICE_TOKEN_HEADER].to_s
    end

    creds
  end

  def initialize(login: nil, password: nil, otp: nil, token: nil)
    @login = login
    @password = password
    @otp = otp
    @via_params = false
    set_token(token)
  end

  # Treat the login and password as potential OAuth access tokens.
  #
  # Returns nothing.
  def initialize_token_from_login_or_password
    # login not used in response therefore safe to use here
    if AccessTokens.oauth_access_token?(login) && password =~ OAUTH_BASIC_PASSWORD # rubocop:disable GitHub/DoNotAllowLogin
      set_token(login) # rubocop:disable GitHub/DoNotAllowLogin
    elsif AccessTokens.authnd_token?(login) && password =~ OAUTH_BASIC_PASSWORD # rubocop:disable GitHub/DoNotAllowLogin
      set_token(login) # rubocop:disable GitHub/DoNotAllowLogin
    elsif AccessTokens.access_token?(password)
      set_token(password)
    end
  end

  # Are the accumulated credentials sufficient to attempt authentication.
  #
  # Returns true if login and password or a token are present.
  def credentials_present?
    login_password_present? || token_present? || exchange_token_present_and_supported_as_primary?
  end

  # Are the username and password both present to attempt authentication?
  #
  # Returns true if login and password are present and false otherwise.
  def login_password_present?
    # login not used in response therefore safe to use here.
    login.present? && password.present? # rubocop:disable GitHub/DoNotAllowLogin
  end

  # Is the token present to attempt authentication?
  #
  # Returns true if a token is present and false otherwise.
  def token_present?
    token.present?
  end

  # Is the internal exchange token present and supported for primary auth?
  #
  # Returns true if the internal exchange token is present and usable for primary authentication.
  def exchange_token_present_and_supported_as_primary?
    return @exchange_token_present_and_supported_as_primary if defined?(@exchange_token_present_and_supported_as_primary)

    @exchange_token_present_and_supported_as_primary =
      internal_exchange_token.present? && GitHub.flipper[:internal_exchange_token_primary_cred_attemptable].enabled?
  end

  def set_token(token)
    # don't set token if it contains non-ascii characters
    # see https://github.com/github/github/issues/65370
    if token && token.ascii_only?
      self.token = token
    end
  end

  # Was this token set via query params?
  #
  # Returns true if the token was set via query params and false if set via
  # headers or basic auth.
  def via_params?
    !!@via_params
  end

  def proxima_service_token_present?
    !!@proxima_service_token
  end
end
