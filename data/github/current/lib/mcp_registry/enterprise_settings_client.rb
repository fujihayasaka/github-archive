# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"

module McpRegistry
  class EnterpriseSettingsClient
    OPEN_TIMEOUT = T.let(5, Integer)
    READ_TIMEOUT = T.let(10, Integer)

    ENTERPRISE_API_VERSION = "v1.0"
    MCP_REGISTRY_TOKEN_SCOPE = "mcp_registry"

    # Maps internal copilot policy config values to the MCP registry service API values.
    POLICY_TO_REGISTRY = T.let({
      "enabled" => "enabled",
      "disabled" => "disabled",
      "no_policy" => "organizations_decide",
    }.freeze, T::Hash[String, String])

    # Maps MCP registry service API values back to internal copilot policy config values.
    REGISTRY_TO_POLICY = T.let({
      "enabled" => "enabled",
      "disabled" => "disabled",
      "organizations_decide" => "no_policy",
    }.freeze, T::Hash[String, String])

    class ApiError < StandardError
      sig { returns(Integer) }
      attr_reader :status

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :body

      sig { params(status: Integer, body: T::Hash[String, T.untyped]).void }
      def initialize(status:, body:)
        @status = status
        @body = body
        super(body["error"] || "API error (#{status})")
      end
    end

    # Return the settings for an enterprise
    #
    # GET /enterprise/v1.0/{enterpriseID}/settings
    sig { params(enterprise_id: Integer, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.get_settings(enterprise_id:, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{enterprise_id}/settings")
      response = http_request(:get, uri, token: token)
      handle_response(response)
    end

    # Update the settings for an enterprise
    #
    # PATCH /enterprise/v1.0/{enterpriseID}/settings
    sig { params(enterprise_id: Integer, block_local_servers: T.nilable(T::Boolean), mcp_policy: T.nilable(String), token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.update_settings(enterprise_id:, block_local_servers: nil, mcp_policy: nil, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{enterprise_id}/settings")
      body = {}
      body[:block_local_servers] = block_local_servers unless block_local_servers.nil?
      body[:mcp_policy] = mcp_policy if mcp_policy.present?
      response = http_request(:patch, uri, body: body, token: token)
      handle_response(response)
    end

    class << self
      private

      sig { params(path: String).returns(URI::HTTP) }
      def build_uri(path)
        url = "#{GitHub.mcp_registry_url}#{path}"
        T.cast(URI(url), URI::HTTP)
      end

      sig { params(method: Symbol, uri: URI::HTTP, body: T.nilable(T::Hash[String, T.untyped]), token: T.nilable(String)).returns(Net::HTTPResponse) }
      def http_request(method, uri, body: nil, token: nil)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = case method
        when :get then Net::HTTP::Get.new(uri)
        when :post then Net::HTTP::Post.new(uri)
        when :patch then Net::HTTP::Patch.new(uri)
        when :delete then Net::HTTP::Delete.new(uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{token}" if token.present?

        if body.present?
          request.body = body.to_json
        end

        http.request(request)
      end

      sig { params(response: Net::HTTPResponse).returns(T::Hash[String, T.untyped]) }
      def handle_response(response)
        parsed_body = if response.body.present?
          JSON.parse(T.must(response.body))
        else
          {}
        end

        status = response.code.to_i
        if status >= 200 && status < 300
          parsed_body
        else
          raise ApiError.new(status: status, body: parsed_body)
        end
      rescue JSON::ParserError => e
        raise ApiError.new(status: response.code.to_i, body: { "error" => "Invalid response from MCP Registry" })
      end
    end
  end
end
