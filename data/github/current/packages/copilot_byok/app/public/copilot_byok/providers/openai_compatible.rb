# typed: strict
# frozen_string_literal: true

class CopilotByok::Providers::OpenAICompatible
  sig { params(base_url: T.nilable(String), api_key: String).returns(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def self.fetch_models(base_url, api_key)
    begin
      uri = URI.parse(base_url || "")
      unless uri.is_a?(URI::HTTPS) && uri.scheme && uri.host
        raise CopilotByok::Providers::InvalidURLError
      end
    rescue URI::InvalidURIError
      raise CopilotByok::Providers::InvalidURLError
    end

    base_uri = "#{uri.scheme}://#{uri.host}"
    base_uri << ":#{uri.port}" if uri.port && uri.port != uri.default_port
    base_path = (uri.path || "").chomp("/")
    new(hostname: base_uri, base_path: base_path, api_key: api_key).fetch_models
  end

  sig { params(hostname: String, base_path: String, api_key: String).void }
  def initialize(hostname:, base_path:, api_key:)
    @base_path = base_path
    @api_key = api_key
    @connection = T.let(new_connection(hostname), ::GitHub::FaradayClient::External)
  end

  sig { returns T::Array[CopilotByok::Types::SelectorCustomModel] }
  def fetch_models
    resp = @connection.get("#{@base_path}/models") # https://platform.openai.com/docs/api-reference/models
    raise CopilotByok::Providers::UnauthorizedError if resp.status == 401
    return [] unless resp.success?

    openai_models = resp.body["data"]
    openai_models.map { |openai_model| openai_model_to_custom_model(openai_model) }
  end

  private

  sig { params(openai_model: T::Hash[String, T.untyped]).returns(CopilotByok::Types::SelectorCustomModel) }
  def openai_model_to_custom_model(openai_model)
    created_at = if openai_model["created"]
      Time.at(openai_model["created"]).utc
    else
      Time.now.utc
    end

    CopilotByok::Types::SelectorCustomModel.new(
      slug: openai_model["id"],
      createdAt: created_at
    )
  end

  sig { params(hostname: String).returns ::GitHub::FaradayClient::External }
  def new_connection(hostname)
    ::GitHub::FaradayClient::External.new(hostname) do |conn|
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
