# typed: true
# frozen_string_literal: true

class Actions::Proxima::TokenGenerator
  extend T::Sig

  def initialize(**kwargs)
    @connection = kwargs.fetch(:connection)

    @base_url = kwargs.fetch(:base_url) { "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}" }
    @app_id = kwargs.fetch(:app_id) { ENV["ACTIONS_TEMPLATE_LOADER_APP_ID"] }
    @app_pem = kwargs.fetch(:app_pem) { ENV["ACTIONS_TEMPLATE_LOADER_APP_PEM"] }
    @installation_id = kwargs.fetch(:installation_id) { ENV["ACTIONS_TEMPLATE_LOADER_APP_INSTALLATION_ID"] }
  end

  attr_reader :connection, :app_id, :app_pem, :installation_id

  sig { returns(String) }
  def generate_token
    jwt = encode_jwt(app_id, app_pem)
    get_access_token(installation_id, jwt)
  end

  private

  def encode_jwt(app_id, private_pem)
    private_key = OpenSSL::PKey::RSA.new(private_pem)

    payload = {
      # issued at time, 60 seconds in the past to allow for clock drift
      iat: Time.now.to_i - 60,
      # JWT expiration time (10 minute maximum)
      exp: Time.now.to_i + (10 * 60),
      # GitHub App"s identifier
      iss: app_id
    }

    JWT.encode(payload, private_key, "RS256")
  end

  def get_access_token(installation_id, jwt)
    access_token_url = URI("/app/installations/#{installation_id}/access_tokens")

    response = connection.post do |req|
      req.url access_token_url.to_s
      req.headers["Authorization"] = "Bearer #{jwt}"
      req.headers["Accept"] = "application/vnd.github+json"
    end

    if !response.success?
      raise Actions::Proxima::WorkflowTemplatesError.new("request failed",
        url: response.env.url,
        status: response.status,
        body: response.body,
      )
    end

    body = GitHub::JSON.decode(response.body)
    body["token"]
  rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout, Faraday::ConnectionFailed => e
    raise Actions::Proxima::WorkflowTemplatesError.new("could not establish connection: #{e.message}",
      url: access_token_url,
      status: -1,
      errors: [e],
    )
  rescue Yajl::ParseError => e
    raise Actions::Proxima::WorkflowTemplatesError.new("failed to parse response: #{e.message}",
      url: response.env.url,
      status: response.status,
      body: response.body,
      errors: [e],
    )
  end
end
