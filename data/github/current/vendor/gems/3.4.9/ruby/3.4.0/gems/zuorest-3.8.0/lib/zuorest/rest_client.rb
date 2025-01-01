require "base64"
require "faraday"
require "faraday_middleware"
require "oauth2"
require "zuorest/api"
require "zuorest/token_storage"
require "zuorest/token_storage/memory"

class Zuorest::RestClient
  extend Forwardable
  include Zuorest::Api

  DEFAULT_TIMEOUT = 60

  def_delegators :connection_options, :timeout, :timeout=, :open_timeout, :open_timeout=

  attr_accessor :debug, :logger, :name, :token_storage

  class NullLogger
    def info(*, **)
    end
  end

  def initialize(
    name: "zuorest",
    server_url:,
    access_key_id:,
    secret_access_key:,
    client_id:,
    client_secret:,
    apm_server_url: nil,
    apm_username: nil,
    apm_api_token: nil,
    timeout: DEFAULT_TIMEOUT,
    open_timeout: DEFAULT_TIMEOUT,
    logger: NullLogger.new,
    token_storage: nil,
    adapter: Faraday.default_adapter
  )
    @server_url = server_url
    @access_key_id = access_key_id
    @secret_access_key = secret_access_key
    @apm_server_url = apm_server_url
    @apm_username = apm_username
    @apm_api_token = apm_api_token
    @default_headers = {
      "apiaccesskeyid" => access_key_id,
      "apisecretaccesskey" => secret_access_key,
      "Content-Type" => "application/json"
    }

    @name = name
    @logger = logger
    @debug = false

    @client_id = client_id
    @client_secret = client_secret

    connection_options = {
      request: {
        open_timeout: open_timeout,
        timeout: timeout
      }
    }
    @oauth2_client = OAuth2::Client.new(
      client_id,
      client_secret,
      site: server_url,
      auth_scheme: :request_body,
      logger: logger,
      connection_opts: connection_options,
      connection_build: lambda do |conn|
        conn.request :url_encoded
        yield conn if block_given?

        conn.adapter adapter
      end
    )

    # Initialize token storage
    @token_storage = token_storage || Zuorest::TokenStorage::Memory.new
    @token_storage_key = Zuorest::TokenStorage.generate_key(client_id, server_url)
    @cached_token = nil

    connection_options.merge!(url: server_url, headers: default_headers)
    @connection = Faraday.new(connection_options) do |conn|
      conn.request :json
      conn.request :multipart
      conn.response :json, content_type: /\bjson$/

      yield conn if block_given?

      conn.adapter adapter
    end
  end

  def post(path, body: nil, headers: nil, params: nil, url_template: nil)
    handle_response(
      connection.post(path, body, headers) do |req|
        if params.present?
          req.params.update(params)
        end
        req.options.context = { "url.template" => url_template } if url_template
      end,
      method: :post,
      path:
    )
  end

  def get(path, params: nil, headers: nil, url_template: nil)
    handle_response(
      connection.get(path, params, headers) do |req|
        req.options.context = { "url.template" => url_template } if url_template
      end,
      method: :get,
      path:
    )
  end

  def put(path, body: nil, headers: nil, url_template: nil)
    handle_response(
      connection.put(path, body, headers) do |req|
        req.options.context = { "url.template" => url_template } if url_template
      end,
      method: :put,
      path:
    )
  end

  def delete(path, headers: nil, url_template: nil)
    handle_response(
      connection.delete(path) do |req|
        req.headers.merge!(headers.to_h) if headers
        req.options.context = { "url.template" => url_template } if url_template
      end,
      method: :delete,
      path:
    )
  end

  def raw_get(path, headers = {}, url_template: nil)
    connection = Faraday.new(url: server_url, headers: default_headers) do |conn|
      conn.options.open_timeout = open_timeout
      conn.options.timeout = timeout

      yield conn if block_given?

      conn.adapter Faraday.default_adapter
    end

    connection.get do |req|
      req.url path
      headers.each do |key, value|
        req.headers[key] = value
      end
      req.options.context = { "url.template" => url_template } if url_template
    end
  end

  def oauth_get(path, params: nil, headers: nil, url_template: nil)
    req_headers = headers.to_h.dup
    req_headers = oauth_header.merge(req_headers)
    
    handle_response(
      connection.get(path, params, req_headers) do |req|
        req.options.context = { "url.template" => url_template } if url_template
      end,
      method: :get,
      path: path
    )
  end

  # Internal: These readers are only used for testing and should not be used
  # outside of the gem code as the API may change
  attr_reader :client_id, :client_secret

  private

  attr_reader :connection, :server_url, :default_headers, :oauth2_client, :token_storage_key
  attr_accessor :cached_token

  def oauth_header
    token = ensure_token_is_fresh
    { "Authorization" => "Bearer %s" % token.token }
  end

  # Private: Get a Zuora Advanced Payment Manager (APM) REST API URL
  #
  # Requires APM-specific client configuration.
  #
  # This is needed since APM uses a different hostname than the general Zuora REST API.
  # See https://www.zuora.com/developer/api-references/collections/overview/ for details.
  #
  # path - String URL path (e.g. "/api/v1/subscription_payment_runs")
  #
  # Returns a String
  def apm_url(path)
    URI::join(@apm_server_url, path).to_s
  end

  # Private: Get the authN header needed for Zuora Advanced Payment Manager (APM) API requests.
  #
  # Requires APM-specific client configuration.
  #
  # This is needed since APM uses a different authN scheme than the general Zuora REST API.
  # See https://www.zuora.com/developer/api-references/collections/overview/ for details.
  #
  # Returns a Hash
  def apm_auth_header
    value = Base64.strict_encode64("#{@apm_username}:#{@apm_api_token}")
    { "Authorization" => "Basic #{value}"}
  end

  # Ensures that a fresh OAuth token is available and returns it
  # Uses the cached token if it's still valid, otherwise fetches a new one
  #
  # @return [OAuth2::AccessToken] A valid, non-expired OAuth2::AccessToken
  def ensure_token_is_fresh
    # Use cached token if it exists and is not expired
    if cached_token && !cached_token.expired?
      return cached_token
    end

    # Try to get token from storage
    token = token_from_storage

    # If no token or token is expired, fetch a new one
    if token.nil? || token.expired?
      token = oauth2_client.client_credentials.get_token
      # Store token data
      token_data = token.to_hash.transform_keys(&:to_s)
      token_storage.store(token_storage_key, token_data)
    end

    # Update the cached token
    self.cached_token = token

    token
  end

  # Retrieves an OAuth token from the token storage
  #
  # @return [OAuth2::AccessToken, nil] The token object or nil if not found or expired
  def token_from_storage
    token_data = token_storage.get(token_storage_key)
    return nil if token_data.nil?

    begin
      # Make sure we're working with string keys
      token_data = token_data.transform_keys(&:to_s) if token_data.is_a?(Hash)
      OAuth2::AccessToken.from_hash(oauth2_client, token_data)
    rescue OAuth2::Error => e
      logger.info("Error deserializing token", { error: e.message }) if debug
      nil
    end
  end

  # Stores an OAuth token in the token storage and updates local cache
  #
  # @param token [OAuth2::AccessToken] The token to store
  # @return [void]
  def store_token_in_storage(token)
    token_data = token.to_hash.transform_keys(&:to_s)
    token_storage.store(token_storage_key, token_data)
    self.cached_token = token
  end

  def connection_options
    connection.options
  end

  # Response is a Faraday::Response
  def handle_response(response, method:, path:)
    unless response.success?
      if response.status == 429
        raise Zuorest::TooManyRequestsError.new(response.status, response.body, response.headers)
      elsif response.status == 504
        raise Zuorest::GatewayTimeoutError.new(response.status, response.body, response.headers)
      else
        raise Zuorest::HttpError.new(response.status, response.body, response.headers)
      end
    end

    if debug
      if response.body.nil? || response.body.empty?
        logger.info("blank response body", {
          "gh.billing.zuora.response.status" => response.status,
          "gh.billing.zuora.response.headers" => response.headers,
          "gh.billing.zuora.response.body" => response.body,
          "gh.billing.zuora.request.method" => method,
          "gh.billing.zuora.request.path" => path,
          "gh.zuorest.client.name" => name
        })
      end
    end

    response.body
  end
end
