# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::Xai
  sig { params(api_key: String).returns(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def self.fetch_models(api_key)
    new(api_key: api_key).fetch_models
  end

  sig { params(api_key: String).void }
  def initialize(api_key:)
    @api_key = api_key
    @connection = T.let(new_connection, ::GitHub::FaradayClient::External)
  end

  sig { returns(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def fetch_models
    resp = @connection.get("/v1/models") # https://docs.x.ai/docs/api-reference#list-models
    raise CopilotByok::Providers::UnauthorizedError if resp.status == 400
    return [] unless resp.success?

    models = resp.body["data"]
    models.map { |model| provider_model_to_custom_model(model) }
  end

  private

  sig { params(provider_model: T::Hash[String, T.untyped]).returns(CopilotByok::Types::SelectorCustomModel) }
  def provider_model_to_custom_model(provider_model)
    CopilotByok::Types::SelectorCustomModel.new(
      slug: provider_model["id"],
      createdAt: Time.at(provider_model["created"]).utc
    )
  end

  sig { returns(::GitHub::FaradayClient::External) }
  def new_connection
    ::GitHub::FaradayClient::External.new(GitHub.xai_api_url) do |conn|
      conn.headers["Authorization"] = "Bearer #{@api_key}"
      conn.request :json
      conn.response :json
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::CopilotByok::SERVICE_NAME
    end
  end
end
