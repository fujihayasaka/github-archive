# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"
require "erb"

module McpRegistry
  # API client for enterprise MCP allowlist operations.
  # Calls the external MCP Registry service at GitHub.mcp_registry_url.
  #
  # TODO: Migrate from raw Net::HTTP to GitHub::FaradayClient::Internal for
  # standard middleware (retry, circuit breaker, Datadog stats, request ID).
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
        super(body["error"] || "API error (#{status})")
      end
    end

    # List all allowlists for an enterprise.
    sig { params(enterprise_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_allowlists(enterprise_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "allowlists"), token: token)
    end

    # Get a single allowlist.
    sig { params(enterprise_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.get_allowlist(enterprise_id:, allowlist_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "allowlists", allowlist_id), token: token)
    end

    # Create a new allowlist.
    sig { params(enterprise_id: String, name: String, description: T.nilable(String), actor_id: T.nilable(Integer), token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.create_allowlist(enterprise_id:, name:, description: nil, actor_id: nil, token: nil)
      body = { "name" => name }
      body["description"] = description if description.present?
      body["updated_by"] = actor_id if actor_id.present?
      uri = build_uri(enterprise_path(enterprise_id, "allowlists"))
      response = http_request(:post, uri, body: body, token: token)
      handle_response(response)
    end

    # Update an existing allowlist's name and/or description.
    sig { params(enterprise_id: String, allowlist_id: String, name: T.nilable(String), description: T.nilable(String), actor_id: T.nilable(Integer), token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.update_allowlist(enterprise_id:, allowlist_id:, name: nil, description: nil, actor_id: nil, token: nil)
      body = T.let({}, T::Hash[String, T.untyped])
      body["name"] = name if name.present?
      body["description"] = description unless description.nil?
      body["updated_by"] = actor_id if actor_id.present?
      uri = build_uri(enterprise_path(enterprise_id, "allowlists", allowlist_id))
      response = http_request(:patch, uri, body: body, token: token)
      handle_response(response)
    end

    # Delete an allowlist.
    sig { params(enterprise_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.delete_allowlist(enterprise_id:, allowlist_id:, token: nil)
      simple_request(:delete, enterprise_path(enterprise_id, "allowlists", allowlist_id), token: token)
    end

    # List all allowlist assignments across all namespaces in an enterprise.
    sig { params(enterprise_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_assignments(enterprise_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "assignments"), token: token)
    end

    # Get an allowlist assignment for a namespace (enterprise or organization).
    sig { params(enterprise_id: String, namespace_type: String, namespace_id: String, token: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.get_allowlist_assignment(enterprise_id:, namespace_type:, namespace_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "namespaces", namespace_type, namespace_id, "assignment"), token: token)
    rescue ApiError => e
      return nil if e.status == 404
      raise
    end

    # Assign an allowlist to a namespace (enterprise or organization).
    # Returns 409 Conflict if an assignment already exists for the namespace.
    sig { params(enterprise_id: String, namespace_type: String, namespace_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.assign_allowlist(enterprise_id:, namespace_type:, namespace_id:, allowlist_id:, token: nil)
      body = { "allowlist_public_id" => allowlist_id }
      uri = build_uri(enterprise_path(enterprise_id, "namespaces", namespace_type, namespace_id, "assignment"))
      response = http_request(:put, uri, body: body, token: token)
      handle_response(response)
    end

    # Remove the allowlist assignment from a namespace.
    sig { params(enterprise_id: String, namespace_type: String, namespace_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.unassign_allowlist(enterprise_id:, namespace_type:, namespace_id:, token: nil)
      simple_request(:delete, enterprise_path(enterprise_id, "namespaces", namespace_type, namespace_id, "assignment"), token: token)
    end

    PUBLIC_API_VERSION = "v0.1"

    # List all servers in the GitHub MCP registry.
    sig { params(search: T.nilable(String), page: Integer, per_page: Integer, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_servers(search: nil, page: 1, per_page: 30, token: nil)
      uri = build_uri("/#{PUBLIC_API_VERSION}/servers")
      query_params = { page: page, per_page: per_page, version: "latest", sort: "stargazercount", direction: "desc" }
      query_params[:search] = search if search.present?
      uri.query = URI.encode_www_form(query_params)
      handle_response(http_request(:get, uri, token: token))
    end

    # Add a server to an allowlist, pinning the specified version (defaults to "latest").
    sig { params(enterprise_id: String, allowlist_id: String, server_id: String, version: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.add_server_to_allowlist(enterprise_id:, allowlist_id:, server_id:, version: "latest", token: nil)
      uri = build_uri(enterprise_path(enterprise_id, "allowlists", allowlist_id, "servers", server_id))
      body = { "version" => version }
      response = http_request(:put, uri, body: body, token: token)
      handle_response(response)
    end

    # Remove a server from an allowlist.
    sig { params(enterprise_id: String, allowlist_id: String, server_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.remove_server_from_allowlist(enterprise_id:, allowlist_id:, server_id:, token: nil)
      simple_request(:delete, enterprise_path(enterprise_id, "allowlists", allowlist_id, "servers", server_id), token: token)
    end

    # List servers associated with an allowlist.
    sig { params(enterprise_id: String, allowlist_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_allowlist_servers(enterprise_id:, allowlist_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "allowlists", allowlist_id, "servers"), token: token)
    end

    # Get all entries (remotes and packages) for a server within an allowlist.
    sig { params(enterprise_id: String, allowlist_id: String, server_id: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.list_server_entries(enterprise_id:, allowlist_id:, server_id:, token: nil)
      simple_request(:get, enterprise_path(enterprise_id, "allowlists", allowlist_id, "servers", server_id, "entries"), token: token)
    end

    # Update selected entries (remotes/packages) for a server within an allowlist.
    # The entries array should contain hashes like {"type" => "package", "package_id" => 307}
    # or {"type" => "remote", "transport_id" => 101} for transport-backed remotes,
    # or {"type" => "remote", "remote_url" => "https://...", "remote_transport_type" => "streamable-http"}
    # for URL-based remotes from version_metadata.
    sig { params(enterprise_id: String, allowlist_id: String, server_id: String, entries: T::Array[T::Hash[String, T.untyped]], token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.update_server_entries(enterprise_id:, allowlist_id:, server_id:, entries:, token: nil)
      body = { "entries" => entries }
      uri = build_uri(enterprise_path(enterprise_id, "allowlists", allowlist_id, "servers", server_id, "entries"))
      response = http_request(:put, uri, body: body, token: token)
      handle_response(response)
    end

    class << self
      private

      # Builds an enterprise API path with URL-encoded segments.
      sig { params(enterprise_id: String, segments: String).returns(String) }
      def enterprise_path(enterprise_id, *segments)
        encoded = segments.map { |s| encode_path_segment(s) }.join("/")
        "/enterprise/#{ENTERPRISE_API_VERSION}/#{encode_path_segment(enterprise_id)}/#{encoded}"
      end

      # Shortcut for simple API calls that only need method + path + token.
      sig { params(method: Symbol, path: String, token: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
      def simple_request(method, path, token: nil)
        handle_response(http_request(method, build_uri(path), token: token))
      end

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
        when :put then Net::HTTP::Put.new(uri)
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

        # Handle case where the API returns an array directly instead of a hash
        if parsed_body.is_a?(Array)
          parsed_body = { "items" => parsed_body }
        end

        status = response.code.to_i
        if status >= 200 && status < 300
          parsed_body
        else
          raise ApiError.new(status: status, body: parsed_body)
        end
      rescue JSON::ParserError
        raise ApiError.new(status: response.code.to_i, body: { "error" => "Invalid response from MCP Registry" })
      end
    end
  end
end
