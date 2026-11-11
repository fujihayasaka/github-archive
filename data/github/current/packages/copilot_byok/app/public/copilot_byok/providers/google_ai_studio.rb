# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::GoogleAiStudio
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
    resp = @connection.get("/v1beta/models", { pageSize: 1000 }) # https://ai.google.dev/api/models#method:-models.list
    # A 400 Bad Request response is returned for an invalid API key:
    raise CopilotByok::Providers::UnauthorizedError if resp.status == 400
    return [] unless resp.success?

    models = resp.body["models"]
    models.map { |model| provider_model_to_custom_model(model) }.compact
  end

  private

  sig { params(provider_model: T::Hash[String, T.untyped]).returns(T.nilable(CopilotByok::Types::SelectorCustomModel)) }
  def provider_model_to_custom_model(provider_model)
    # From https://ai.google.dev/api/models#Model
    # > The model's supported generation methods.
    # > The corresponding API method names are defined as Pascal case strings, such as generateMessage and generateContent.
    # We get values here like embedContent, and generateAnswer. But for Copilot we only want models that support text generation.
    # So we filter to only those that support "generateContent".
    return nil unless provider_model["supportedGenerationMethods"]&.include?("generateContent")

    # Google returns model ids with a "models/" prefix, it reads nicer on the UI without it. So lets strip it.
    # e.g. "models/gemini-2.5-flash-preview-09-2025"
    slug = provider_model["name"].gsub(/\Amodels\//, "")

    CopilotByok::Types::SelectorCustomModel.new(
      slug: slug,
      name: provider_model["displayName"],
    )
  end

  sig { returns(::GitHub::FaradayClient::External) }
  def new_connection
    ::GitHub::FaradayClient::External.new(GitHub.google_ai_studio_api_url) do |conn|
      conn.headers["X-goog-api-key"] = @api_key
      conn.request :json
      conn.response :json
      conn.adapter Faraday.default_adapter
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats,
        service_name: GitHub::Config::CopilotByok::SERVICE_NAME
    end
  end
end
