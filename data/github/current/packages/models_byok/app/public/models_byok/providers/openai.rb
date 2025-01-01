# typed: strict
# frozen_string_literal: true

class ModelsByok::Providers::OpenAI
  class UnauthorizedError < StandardError; end

  sig { params(api_key: String).returns(T::Array[ModelsByok::Types::SelectorCustomModel]) }
  def self.fetch_models(api_key)
    new(api_key: api_key).fetch_models
  end

  sig { params(api_key: String).void }
  def initialize(api_key:)
    @api_key = api_key
    @connection = T.let(new_connection, ::GitHub::FaradayClient::External)
  end

  sig { returns T::Array[ModelsByok::Types::SelectorCustomModel] }
  def fetch_models
    resp = @connection.get("/v1/models") # https://platform.openai.com/docs/api-reference/models
    raise UnauthorizedError if resp.status == 401
    return [] unless resp.success?

    openai_models = resp.body["data"]
    openai_models.map { |openai_model| openai_model_to_custom_model(openai_model) }
  end

  private

  sig { params(openai_model: T::Hash[String, T.untyped]).returns(ModelsByok::Types::SelectorCustomModel) }
  def openai_model_to_custom_model(openai_model)
    ModelsByok::Types::SelectorCustomModel.new(
      slug: openai_model["id"],
      createdAt: Time.at(openai_model["created"]).utc
    )
  end

  sig { returns ::GitHub::FaradayClient::External }
  def new_connection
    ::GitHub::FaradayClient::External.new(GitHub.openai_api_url) do |conn|
      conn.headers["Authorization"] = "Bearer #{@api_key}"
      conn.request :json
      conn.response :json
      conn.options[:timeout] = 60_000
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::ModelsByok::SERVICE_NAME
    end
  end
end
