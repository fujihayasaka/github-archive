# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"

module McpRegistry
  class RestApiClient
    LIMIT = T.let(30, Integer)
    OPEN_TIMEOUT = T.let(5, Integer)
    READ_TIMEOUT = T.let(10, Integer)

    class ServerNotFoundError < StandardError; end

    sig { returns(String) }
    def self.servers_path
      "/v0.1/servers"
    end

    sig { params(page: Integer, per_page: Integer, search: T.nilable(String), exclude_readme: T::Boolean).returns(T::Hash[String, T.untyped]) }
    def self.fetch_servers(page: 1, per_page: LIMIT, search: nil, exclude_readme: false)
      # Use the unified servers endpoint for both list and search with page-based pagination
      list_servers(page: page, per_page: per_page, search: search, exclude_readme: exclude_readme)
    end

    sig { params(page: Integer, per_page: Integer, search: T.nilable(String), exclude_readme: T::Boolean).returns(T::Hash[String, T.untyped]) }
    def self.list_servers(page: 1, per_page: LIMIT, search: nil, exclude_readme: false)
      # v0.1 API uses the same endpoint for both list and search
      uri = URI("#{GitHub.mcp_registry_url}#{servers_path}")
      params = { page: page, per_page: per_page, version: "latest", sort: "stargazercount", direction: "desc" }
      params[:search] = search if search.present?
      params[:exclude_readme] = true if exclude_readme

      uri.query = URI.encode_www_form(params)

      response = http_get(T.cast(uri, URI::HTTP))

      if response.code == "200"
        raw_data = JSON.parse(T.must(response.body))
        transform_servers_response(raw_data)
      else
        Rails.logger.info "MCP Registry API returned #{response.code}: #{response.body}"
        empty_servers_response
      end
    rescue StandardError => e
      Rails.logger.error "Failed to list servers from MCP Registry API: #{e.message}"
      empty_servers_response
    end

    sig { params(server_id: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_server(server_id)
      uri = URI("#{GitHub.mcp_registry_url}#{servers_path}/#{server_id}")

      # Fetch the data from the API with Accept header
      response = http_get(T.cast(uri, URI::HTTP))

      if response.code == "200"
        raw_server = JSON.parse(T.must(response.body))
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
    rescue StandardError => e
      Rails.logger.error "Failed to fetch server from MCP Registry API: #{e.message}"
      {}
    end

    sig { params(name: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_server_by_name(name)
      # URL-encode only slashes in the server name (slashes become %2F)
      # Example: io.github.netdata/mcp-server becomes io.github.netdata%2Fmcp-server
      encoded_name = name.gsub("/", "%2F")

      # v0.1 API uses: /v0.1/servers/{serverName}/versions/latest
      # Old API uses: /v0/servers/by-name/{serverName}
      if FeatureFlag.vexi.enabled?(:mcp_registry_oss_v0_1_api, default: false)
        uri = URI("#{GitHub.mcp_registry_url}#{servers_path}/#{encoded_name}/versions/latest")
      else
        uri = URI("#{GitHub.mcp_registry_url}/v0/servers/by-name/#{encoded_name}")
      end

      response = http_get(T.cast(uri, URI::HTTP))

      if response.code == "200"
        raw_server = JSON.parse(T.must(response.body))
        transform_single_server(raw_server)
      elsif response.code == "404"
        Rails.logger.info "MCP Registry API returned 404 for server: #{name}"
        raise ServerNotFoundError, "Server not found"
      else
        Rails.logger.info "MCP Registry API (by-name) returned #{response.code}: #{response.body}"
        {}
      end
    rescue ServerNotFoundError
      # Re-raise ServerNotFoundError so it bubbles up to the controller
      raise
    rescue StandardError => e
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
          "total" => 0,
          "total_pages" => 0
        }
      }
    end

    # Transform the raw API response to flatten server data for easier frontend consumption
    sig { params(raw_data: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_servers_response(raw_data)
      return raw_data unless raw_data["servers"].is_a?(Array)

      transformed_servers = raw_data["servers"].map { |server| transform_server_data(server) }

      # Handle metadata from different API versions:
      # - v0.1 API: metadata["total"] = total count, metadata["count"] = current page count
      # - v0 2025-09-15 API: metadata["total"] = total count, metadata["count"] = current page count
      # - Old v0 API (without total field): metadata["count"] = total count (NOT current page count)
      metadata = raw_data["metadata"] || {}

      # Check if the API response includes a separate total field
      if metadata.key?("total")
        # v0.1 API and v0 2025-09-15 API both have separate total and count fields
        total_servers = metadata["total"] || 0
        current_page_count = metadata["count"] || transformed_servers.length
      else
        # Old v0 API only has count field which represents total, so we use actual array length for current page
        total_servers = metadata["count"] || 0
        current_page_count = transformed_servers.length
      end

      transformed_metadata = {
        "count" => current_page_count,
        "total" => total_servers,
        "total_pages" => metadata["total_pages"] || metadata["totalPages"] || 0
      }

      # Include nextCursor if present (for cursor-based pagination compatibility)
      next_cursor = metadata["nextCursor"] || metadata["next_cursor"]
      transformed_metadata["next_cursor"] = next_cursor if next_cursor

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
      # Check if this is a search result format (has _meta at top level instead of server wrapper)
      if server.key?("_meta") && !server.key?("server")
        transform_search_result_server_data(server)
      else
        # Always use v0.1 API format
        transform_oss_v0_1_server_data(server)
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

    # Transform server data from the v0.1 API format
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_oss_v0_1_server_data(server)
      server_data = server["server"] || {}
      github_data = server_data.dig("_meta", "io.modelcontextprotocol.registry/publisher-provided", "github") || {}
      repository_data = server_data["repository"] || {}

      base_data = {
        "id" => server_data["name"],
        "name" => server_data["name"],
        "display_name" => github_data["displayName"] || server_data["name"],
        "description" => server_data["description"],
        "url" => repository_data["url"],
        "created_at" => server_data["version"],
        "updated_at" => github_data["pushedAt"],
        "stargazer_count" => github_data["stargazerCount"],
        "owner_avatar_url" => github_data["ownerAvatarUrl"],
        "primary_language" => github_data["primaryLanguage"],
        "primary_language_color" => github_data["primaryLanguageColor"],
        "repo_id" => repository_data["id"],
        "license" => github_data["license"],
        "topics" => github_data["topics"] || [],
        "opengraph_image_url" => github_data["opengraphImageUrl"],
        "uses_custom_opengraph_image" => github_data["usesCustomOpengraphImage"],
        "name_with_owner" => github_data["nameWithOwner"],
        "is_in_organization" => github_data["isInOrganization"],
        "pushed_at" => github_data["pushedAt"],
      }

      # Include the repository object with README from github_data if available
      if repository_data.present?
        base_data["repository"] = repository_data.dup
        # Add README from github_data if present
        if github_data["readme"].present?
          base_data["repository"]["readme"] = github_data["readme"]
        end
      end

      base_data
    end

    # Transform server data from the v0 search endpoint format
    # This format has _meta at the top level with GitHub data nested differently
    sig { params(server: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_search_result_server_data(server)
      github_data = server.dig("_meta", "io.modelcontextprotocol.registry/publisher-provided", "github") || {}

      {
        "id" => server["name"],
        "name" => server["name"],
        "display_name" => github_data["display_name"] || github_data["displayName"] || server["name"],
        "description" => server["description"],
        "url" => server.dig("repository", "url"),
        "created_at" => server["created_at"],
        "updated_at" => github_data["pushed_at"] || github_data["pushedAt"],
        "stargazer_count" => github_data["stargazer_count"] || github_data["stargazerCount"],
        "owner_avatar_url" => github_data["owner_avatar_url"] || github_data["ownerAvatarUrl"],
        "primary_language" => github_data["primary_language"] || github_data["primaryLanguage"],
        "primary_language_color" => github_data["primary_language_color"] || github_data["primaryLanguageColor"],
        "repo_id" => server.dig("repository", "id"),
        "license" => github_data["license"],
        "topics" => github_data["topics"] || [],
        "opengraph_image_url" => github_data["opengraph_image_url"] || github_data["opengraphImageUrl"],
        "uses_custom_opengraph_image" => github_data["uses_custom_opengraph_image"] || github_data["usesCustomOpengraphImage"],
        "name_with_owner" => github_data["name_with_owner"] || github_data["nameWithOwner"],
        "is_in_organization" => github_data["is_in_organization"] || github_data["isInOrganization"],
        "pushed_at" => github_data["pushed_at"] || github_data["pushedAt"],
      }
    end

    # Perform a GET request with explicit timeouts to prevent slow API responses
    # from blocking page render and degrading HPC metrics.
    sig { params(uri: URI::HTTP).returns(Net::HTTPResponse) }
    def self.http_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      http.request(request)
    end
  end
end
