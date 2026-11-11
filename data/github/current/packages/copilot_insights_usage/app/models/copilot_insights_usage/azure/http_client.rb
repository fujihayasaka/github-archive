# typed: strict
# frozen_string_literal: true

class CopilotInsightsUsage::Azure::HttpClient
  extend T::Helpers

  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

  sig { params(storage_config: Copilot::Metrics::Azure::Storage::Config).void }
  def initialize(storage_config:)
    azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
    token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
    token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

    @token_provider = T.let(GitHub::Azure::ApplicationTokenProvider.new(
      storage_config.tenant_id,
      storage_config.client_id,
      storage_config.client_secret,
      token_provider_settings
    ), GitHub::Azure::ApplicationTokenProvider)
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
    end, T.nilable(Faraday::Connection))
  end

  sig { params(method: Symbol, uri: String, params: T::Hash[T.untyped, T.untyped], headers: T::Hash[T.untyped, T.untyped], body: T.untyped).returns(T.untyped) }
  def send_request(method:, uri:, params: {}, headers: {}, body: nil)
    begin
      response = @connection.public_send(method, uri) do |request| # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        request.options.timeout = 20
        request.body = body
        request.headers["Accept"] = "application/json"
        request.headers["Authorization"] = @token_provider.get_authentication_header
        request.params.merge!(params)
        request.headers.merge!(headers)
      end
    rescue Faraday::Error => e
      GitHub.dogstats.increment(
        "copilot_insights_azure_http_client.send_request",
        tags: ["success:false", "error_class:#{e.class}"]
      )
      GitHub.logger.error("failed to send request", { "exception" => e, "code.namespace" => self.class.name, "code.function" => __method__ })
      raise e
    end

    response
  end
end
