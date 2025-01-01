# typed: strict
# frozen_string_literal: true

class McpOauth::RegisterMcpServer
  sig { params(server_url: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.call(server_url:)
    router = McpOauth::Router.new(server_url)
    metadata = router.metadata

    raise McpOauth::ServerRegistrationError, "Missing registration_endpoint" unless metadata[:registration_endpoint]

    perform_dynamic_registration(metadata[:registration_endpoint])
  end

  sig { params(register_uri: String).returns(T::Hash[Symbol, String]) }
  def self.perform_dynamic_registration(register_uri)
    body = { redirect_uris: [McpOauth::Configuration.redirect_uri] }

    response = McpOauth::HttpClient.post(register_uri, body)

    raise McpOauth::ServerRegistrationError, "Registration failed: #{response.status}" unless response.status == 201

    JSON.parse(response.body).slice("client_id", "client_secret").transform_keys(&:to_sym)
  end

  private_class_method :perform_dynamic_registration
end
