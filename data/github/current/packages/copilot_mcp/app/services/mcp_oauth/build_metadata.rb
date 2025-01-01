# typed: strict
# frozen_string_literal: true

class McpOauth::BuildMetadata
  class FetchMetadataError < StandardError; end

  REQUIRED_KEYS = T.let(
    %i[
      issuer
      authorization_endpoint
      token_endpoint
      registration_endpoint
      revocation_endpoint
      revocation_endpoint_auth_methods_supported
      response_types_supported
      code_challenge_methods_supported
      token_endpoint_auth_methods_supported
      grant_types_supported
    ],
    T::Array[Symbol]
  )

  sig do
    params(
      base_url: String,
      fallback_router: T.nilable(McpOauth::Router)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.call(base_url:, fallback_router: nil)
    data = fetch_hardcoded_metadata(base_url)
    data ||= fetch_well_known_metadata(base_url)

    data.merge({
      issuer: data[:issuer] || URI(base_url).to_s,
      authorization_endpoint: data[:authorization_endpoint] || fallback_router&.url_for("/authorize"),
      token_endpoint: data[:token_endpoint] || fallback_router&.url_for("/token"),
      registration_endpoint: data[:registration_endpoint] || fallback_router&.url_for("/register"),
      revocation_endpoint: data[:revocation_endpoint] || fallback_router&.url_for("/revoke"),
      revocation_endpoint_auth_methods_supported: data[:revocation_endpoint_auth_methods_supported] || ["client_secret_post"],
      response_types_supported: data[:response_types_supported] || ["code"],
      code_challenge_methods_supported: data[:code_challenge_methods_supported] || ["S256"],
      token_endpoint_auth_methods_supported: data[:token_endpoint_auth_methods_supported] || ["client_secret_post"],
      grant_types_supported: data[:grant_types_supported] || %w[authorization_code refresh_token]
    })
  end

  sig { params(base_url: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.fetch_hardcoded_metadata(base_url)
    if base_url == "https://www.figma.com"
      {
        authorization_endpoint: "https://www.figma.com/oauth?scope=file_content:read",
        token_endpoint: "https://api.figma.com/v1/oauth/token",
        # use authorization header for the token endpoint
        use_authorization_header: true,
      }
    end
  end
  private_class_method :fetch_hardcoded_metadata

  sig { params(base_url: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.fetch_well_known_metadata(base_url)
    well_known_url = URI.join(base_url.to_s, "/.well-known/oauth-authorization-server").to_s
    response = McpOauth::HttpClient.get(well_known_url)
    JSON.parse(response.body).symbolize_keys
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse JSON from #{well_known_url}: #{e.message}"
    {}
  rescue Faraday::ConnectionFailed, SocketError => e
    Rails.logger.error "Failed to connect to #{well_known_url}: #{e.message}"
    {}
  rescue FetchMetadataError => e
    Rails.logger.error "Unexpected error while fetching metadata from #{well_known_url}: #{e.message}"
    {}
  end
  private_class_method :fetch_well_known_metadata
end
