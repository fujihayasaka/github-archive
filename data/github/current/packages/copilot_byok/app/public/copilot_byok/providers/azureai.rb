# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::AzureAI
  class UnauthorizedError < StandardError; end

  sig { params(api_key: String, deployment_url: String).returns(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def self.fetch_models(api_key, deployment_url)
    new(api_key, deployment_url).fetch_models
  end

  sig { params(api_key: String, deployment_url: String).void }
  def initialize(api_key, deployment_url)
    @api_key = api_key
    @deployment_url = deployment_url
    @connection = T.let(new_connection, ::GitHub::FaradayClient::External)
  end

  sig { returns T::Array[CopilotByok::Types::SelectorCustomModel] }
  def fetch_models
    resp = @connection.get("/openai/models?api-version=2024-10-21") # https://learn.microsoft.com/en-us/rest/api/azureopenai/models/list
    raise UnauthorizedError if resp.status == 401
    return [] unless resp.success?

    azure_openai_models = resp.body["data"]
    azure_openai_models.map { |openai_model| azure_openai_model_to_custom_model(openai_model) }
  end

  private

  sig { params(openai_model: T::Hash[String, T.untyped]).returns(CopilotByok::Types::SelectorCustomModel) }
  def azure_openai_model_to_custom_model(openai_model)
    CopilotByok::Types::SelectorCustomModel.new(
      slug: openai_model["id"],
      createdAt: Time.at(openai_model["created_at"]).utc
    )
  end

  sig { returns ::GitHub::FaradayClient::External }
  def new_connection
    ::GitHub::FaradayClient::External.new(@deployment_url) do |conn|
      conn.headers["Authorization"] = "Bearer #{@api_key}"
      conn.request :json
      conn.response :json
      conn.options[:timeout] = 60_000
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::CopilotByok::SERVICE_NAME
    end
  end
end
