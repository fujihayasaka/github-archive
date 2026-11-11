# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"
require "erb"

module McpRegistry
  # API client for enterprise MCP allowlist operations.
  # Calls the external MCP Registry service at GitHub.mcp_registry_url.
  class EnterpriseAllowlistClient
    OPEN_TIMEOUT = T.let(5, Integer)
    READ_TIMEOUT = T.let(10, Integer)

    ENTERPRISE_API_VERSION = "v1.0"

    class ApiError < StandardError

      sig { returns(Integer) }
      attr_reader :status

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :body

      sig { params(status: Integer, body: T::Hash[String, T.untyped]).void }
      def initialize(status:, body:)
        @status = status
        @body = body
        super(body["message"] || "API error (#{status})")
      end
    end

    # List all allowlists for an enterprise.
    #
    # GET /enterprise/v1.0/{enterpriseID}/allowlists
    sig { params(enterprise_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_allowlists(enterprise_id:, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/allowlists")
      response = http_request(:get, uri, token: token)
      handle_response(response)
    end

    # Get a single allowlist.
    #
    # GET /enterprise/v1.0/{enterpriseID}/allowlists/{allowlistPublicID}
    sig { params(enterprise_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.get_allowlist(enterprise_id:, allowlist_id:, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/allowlists/#{encode_path_segment(allowlist_id)}")
      response = http_request(:get, uri, token: token)
      handle_response(response)
    end

    # Create a new allowlist.
    #
    # POST /enterprise/v1.0/{enterpriseID}/allowlists
    sig { params(enterprise_id: String, name: String, description: T.nilable(String), token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.create_allowlist(enterprise_id:, name:, description: nil, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/allowlists")
      body = { "name" => name }
      body["description"] = description if description.present?
      response = http_request(:post, uri, body: body, token: token)
      handle_response(response)
    end

    # Update an existing allowlist's name and/or description.
    #
    # PATCH /enterprise/v1.0/{enterpriseID}/allowlists/{allowlistPublicID}
    sig { params(enterprise_id: String, allowlist_id: String, name: T.nilable(String), description: T.nilable(String), token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.update_allowlist(enterprise_id:, allowlist_id:, name: nil, description: nil, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/allowlists/#{encode_path_segment(allowlist_id)}")
      body = T.let({}, T::Hash[String, T.untyped])
      body["name"] = name if name.present?
      body["description"] = description unless description.nil?
      response = http_request(:patch, uri, body: body, token: token)
      handle_response(response)
    end

    # Delete an allowlist.
    #
    # DELETE /enterprise/v1.0/{enterpriseID}/allowlists/{allowlistPublicID}
    sig { params(enterprise_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.delete_allowlist(enterprise_id:, allowlist_id:, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/allowlists/#{encode_path_segment(allowlist_id)}")
      response = http_request(:delete, uri, token: token)
      handle_response(response)
    end

    # List all allowlist assignments across all namespaces in an enterprise.
    #
    # GET /enterprise/v1.0/{enterpriseID}/assignments
    sig { params(enterprise_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_assignments(enterprise_id:, token: nil)
      uri = build_uri("/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/assignments")
      response = http_request(:get, uri, token: token)
      handle_response(response)
    end

    class << self
      private

      # URL-encode a single path segment to prevent path traversal.
      sig { params(segment: String).returns(String) }
      def encode_path_segment(segment)
        ERB::Util.url_encode(segment)
      end

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
        raise ApiError.new(status: response.code.to_i, body: { "message" => "Invalid response from MCP Registry" })
      end
    end
  end
end
