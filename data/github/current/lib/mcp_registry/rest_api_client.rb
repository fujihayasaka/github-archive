# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"

module McpRegistry
  class RestApiClient
    SERVERS_PATH = T.let("/v0/servers", String)
    SERVERS_BY_NAME_PATH = T.let("/v0/servers/by-name", String)
    SEARCH_PATH = T.let("/v0/servers/search", String)

    class ServerNotFoundError < StandardError; end

    sig { params(cursor: T.nilable(String), limit: Integer, q: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def self.fetch_servers(cursor: nil, limit: 30, q: nil)
      # If search query is provided, use the search endpoint
      if q.present?
        search_servers(q: q, cursor: cursor, limit: limit)
      else
        list_servers(cursor: cursor, limit: limit)
      end
    end

    sig { params(cursor: T.nilable(String), limit: Integer).returns(T::Hash[String, T.untyped]) }
    def self.list_servers(cursor: nil, limit: 30)
      uri = URI("#{GitHub.mcp_registry_url}#{SERVERS_PATH}")
      params = { limit: limit }
      params[:cursor] = cursor if cursor.present?
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri, { "Accept" => "application/json" })

      if response.code == "200"
        raw_data = JSON.parse(response.body)
        transform_servers_response(raw_data)
      else
        Rails.logger.info "MCP Registry API returned #{response.code}: #{response.body}"
        empty_servers_response
      end
    rescue StandardError => e # rubocop:disable Lint/RescueException
      Rails.logger.error "Failed to list servers from MCP Registry API: #{e.message}"
      empty_servers_response
    end

    sig { params(q: String, cursor: T.nilable(String), limit: Integer).returns(T::Hash[String, T.untyped]) }
    def self.search_servers(q:, cursor: nil, limit: 30)
      uri = URI("#{GitHub.mcp_registry_url}#{SEARCH_PATH}")
      params = { limit: limit, q: q }
      params[:cursor] = cursor if cursor.present?
      uri.query = URI.encode_www_form(params)

      response = Net::HTTP.get_response(uri, { "Accept" => "application/json" })

      if response.code == "200"
        raw_data = JSON.parse(response.body)
        transform_servers_response(raw_data)
      elsif response.code == "400"
        # Handle case where Go service returns 400 for invalid search parameters
        Rails.logger.info "MCP Registry API returned 400 for search query '#{q}': #{response.body}"
        empty_servers_response
      else
        Rails.logger.info "MCP Registry API returned #{response.code}: #{response.body}"
        empty_servers_response
      end
    rescue StandardError => e # rubocop:disable Lint/RescueException
      Rails.logger.error "Failed to search servers from MCP Registry API: #{e.message}"
      empty_servers_response
    end

    sig { params(server_id: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_server(server_id)
      uri = URI("#{GitHub.mcp_registry_url}#{SERVERS_PATH}/#{server_id}")

      # Fetch the data from the API with Accept header
      response = Net::HTTP.get_response(uri, { "Accept" => "application/json" })

      if response.code == "200"
        raw_server = JSON.parse(response.body)
        transform_single_server(raw_server)
      elsif response.code == "404"
        raise ServerNotFoundError, "Server not found"
      else
        Rails.logger.info "MCP Registry API returned #{response.code}: #{response.body}"
        {}
      end
    rescue ServerNotFoundError
      # Re-raise ServerNotFoundError so it bubbles up to the controller
      raise
    rescue StandardError => e # rubocop:disable Lint/RescueException
      Rails.logger.error "Failed to fetch server from MCP Registry API: #{e.message}"
      {}
    end

    sig { params(name: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_server_by_name(name)
      uri = URI("#{GitHub.mcp_registry_url}#{SERVERS_BY_NAME_PATH}/#{name}")
      response = Net::HTTP.get_response(uri, { "Accept" => "application/json" })

      if response.code == "200"
        raw_server = JSON.parse(response.body)
        transform_single_server(raw_server)
      elsif response.code == "404"
        raise ServerNotFoundError, "Server not found"
      else
        Rails.logger.info "MCP Registry API (by-name) returned #{response.code}: #{response.body}"
        {}
      end
    rescue ServerNotFoundError
      # Re-raise ServerNotFoundError so it bubbles up to the controller
      raise
    rescue StandardError => e # rubocop:disable Lint/RescueException
      Rails.logger.error "Failed to fetch server by name from MCP Registry API: #{e.message}"
      {}
    end

    # Returns an empty servers response structure for error cases
    sig { returns(T::Hash[String, T.untyped]) }
    def self.empty_servers_response
      {
        "servers" => [],
        "metadata" => {
          "count" => 0,
          "total" => 0
        }
      }
    end

    # Transform the raw API response to flatten server data for easier frontend consumption
    sig { params(raw_data: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_servers_response(raw_data)
      return raw_data unless raw_data["servers"].is_a?(Array)

      transformed_servers = raw_data["servers"].map { |server| transform_server_data(server) }

      # Handle both next_cursor (from Go service) and cursor for consistency
      metadata = raw_data["metadata"] || {}
      transformed_metadata = {
        "count" => metadata["count"] || 0,
        "total" => metadata["total"] || metadata["count"] || 0
      }

      # Add next_cursor if present (from Go service search)
      if metadata["next_cursor"].present?
        transformed_metadata["next_cursor"] = metadata["next_cursor"]
      end

      {
        "servers" => transformed_servers,
        "metadata" => transformed_metadata
      }
    end

    # Transform a single server for the details endpoint
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_single_server(server)
      transform_server_data(server).merge("raw_data" => server)
    end

    # Shared transformation logic for server data
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_server_data(server)
      if FeatureFlag.vexi.enabled?(:mcp_registry_new_api_format, default: false)
        transform_new_format_server_data(server)
      else
        transform_old_format_server_data(server)
      end
    end

    # Transform server data from the old API format
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_old_format_server_data(server)
      github_data = server.dig("VendorExtensions", "x-github") || {}

      {
        "id" => server["id"],
        "name" => server["name"],
        "display_name" => github_data["display_name"],
        "description" => server["description"],
        "url" => server.dig("repository", "url"),
        "created_at" => server.dig("version_detail", "release_date"),
        "updated_at" => github_data["pushed_at"],
        "stargazer_count" => github_data["stargazer_count"],
        "owner_avatar_url" => github_data["owner_avatar_url"],
        "primary_language" => github_data["primary_language"],
        "primary_language_color" => github_data["primary_language_color"],
        "repo_id" => server.dig("repository", "id"),
        "license" => github_data["license"],
        "topics" => github_data["topics"] || [],
        "opengraph_image_url" => github_data["opengraph_image_url"],
        "uses_custom_opengraph_image" => github_data["uses_custom_opengraph_image"],
        "name_with_owner" => github_data["name_with_owner"],
        "is_in_organization" => github_data["is_in_organization"],
        "pushed_at" => github_data["pushed_at"],
      }
    end

    # Transform server data from the new API format
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_new_format_server_data(server)
      server_data = server["server"] || {}
      github_data = server["x-github"] || {}
      registry_data = server["x-io.modelcontextprotocol.registry"] || {}

      {
        "id" => server_data["id"],
        "name" => server_data["name"],
        "display_name" => github_data["display_name"],
        "description" => server_data["description"],
        "url" => server_data.dig("repository", "url"),
        "created_at" => server_data.dig("version_detail", "release_date"),
        "updated_at" => github_data["pushed_at"],
        "stargazer_count" => github_data["stargazer_count"],
        "owner_avatar_url" => github_data["owner_avatar_url"],
        "primary_language" => github_data["primary_language"],
        "primary_language_color" => github_data["primary_language_color"],
        "repo_id" => server_data.dig("repository", "id"),
        "license" => github_data["license"],
        "topics" => github_data["topics"] || [],
        "opengraph_image_url" => github_data["opengraph_image_url"],
        "uses_custom_opengraph_image" => github_data["uses_custom_opengraph_image"],
        "name_with_owner" => github_data["name_with_owner"],
        "is_in_organization" => github_data["is_in_organization"],
        "pushed_at" => github_data["pushed_at"],
      }
    end
  end
end
