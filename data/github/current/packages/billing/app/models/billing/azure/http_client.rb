# typed: strict
# frozen_string_literal: true

class Billing::Azure::HttpClient
  extend T::Helpers
  include GitHub::Memoizer

  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

  sig { params(storage_config: Billing::Azure::Storage::Config).void }
  def initialize(storage_config:)
    @storage_config = T.let(storage_config, Billing::Azure::Storage::Config)
    @oidc_access_token = T.let(nil, T.nilable(String))
    @oidc_token_expires_at = T.let(nil, T.nilable(Time))
    @auth_method_used = T.let(storage_config.use_oidc? ? "oidc" : "secret", String)

    @connection = T.let(GitHub::FaradayClient::Internal.new do |builder|
      builder.use ::GitHub::FaradayMiddleware::RaiseError
      builder.request :retry,
        methods: [:delete, :get, :head, :merge, :patch, :post, :put],
        retry_statuses: [408, 429, *500...600],
        exceptions: [Errno::ETIMEDOUT, "Timeout::Error", Faraday::TimeoutError, Faraday::RetriableResponse, Faraday::ConnectionFailed],
        interval: 0.05,
        interval_randomness: 0.5,
        backoff_factor: 2
      builder.request :json
      builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
      builder.adapter Faraday.default_adapter
    end, Faraday::Connection)
  end

  sig { params(method: Symbol, uri: String, params: T::Hash[T.untyped, T.untyped], headers: T::Hash[T.untyped, T.untyped], body: T.untyped).returns(T.untyped) }
  def send_request(method:, uri:, params: {}, headers: {}, body: nil)
    begin
      response = connection.send(method, uri) do |request| # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        request.options.timeout = 20
        request.body = body
        request.headers["Accept"] = "application/json"
        request.headers["Authorization"] = authorization_header

        request.params.merge!(params)
        request.headers.merge!(headers)
      end
    rescue Faraday::Error => e
      response_data = e.response || {}
      GitHub.dogstats.increment(
        "billing_azure_http_client.send_request",
        tags: ["success:false", "status:#{response_data[:status] || "unknown"}", "error:#{e.class.name}", "auth:#{@auth_method_used}"]
      )
      raise e
    end

    response
  end

  private

  sig { returns(String) }
  def authorization_header
    if @storage_config.use_oidc?
      "Bearer #{acquire_oidc_token}"
    else
      token_provider.get_authentication_header
    end
  end

  sig { returns(String) }
  def acquire_oidc_token
    token = @oidc_access_token
    expires_at = @oidc_token_expires_at
    if token.nil? || expires_at.nil? || expires_at < Time.now.utc
      result = GitHub::Azure::OIDCTokenProvider.acquire_token(
        config: @storage_config,
        faraday_client_name: "BillingHttpClientOIDC",
        scope: GitHub::Azure::OIDCTokenProvider::AZURE_STORAGE_TOKEN_SCOPE,
      )
      token = result.access_token
      expires_at = Time.now.utc + result.expires_in - GitHub::Azure::OIDCTokenProvider::EXPIRATION_SAFE_THRESHOLD_SECONDS
      @oidc_access_token = token
      @oidc_token_expires_at = expires_at
    end

    token
  end

  sig { returns(GitHub::Azure::ApplicationTokenProvider) }
  memoize def token_provider
    azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
    token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
    token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

    GitHub::Azure::ApplicationTokenProvider.new(
      @storage_config.tenant_id,
      @storage_config.client_id,
      @storage_config.client_secret,
      token_provider_settings
    )
  end

  sig { returns(Faraday::Connection) }
  attr_reader :connection
end
