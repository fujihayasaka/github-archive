# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::Anthropic
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
    resp = @connection.get("/v1/models", { limit: 1000 }) # https://docs.claude.com/en/api/models-list
    raise CopilotByok::Providers::UnauthorizedError if resp.status == 401
    return [] unless resp.success?

    models = resp.body["data"]
    models.map { |model| anthropic_model_to_custom_model(model) }
  end

  private

  sig { params(anthropic_model: T::Hash[String, T.untyped]).returns(CopilotByok::Types::SelectorCustomModel) }
  def anthropic_model_to_custom_model(anthropic_model)
    CopilotByok::Types::SelectorCustomModel.new(
      slug: anthropic_model["id"],
      name: anthropic_model["display_name"],
      createdAt: Time.parse(anthropic_model["created_at"]).utc
    )
  end

  sig { returns(::GitHub::FaradayClient::External) }
  def new_connection
    ::GitHub::FaradayClient::External.new(GitHub.anthropic_api_url) do |conn|
      conn.headers["x-api-key"] = @api_key
      conn.headers["anthropic-version"] = "2023-06-01" # taken from https://docs.claude.com/en/api/overview
      conn.request :json
      conn.response :json
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::CopilotByok::SERVICE_NAME
    end
  end
end
