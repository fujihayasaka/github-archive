# typed: strict
# frozen_string_literal: true

require "net/http"
require "json"

# AgentFinder::RestApiClient is a thin HTTP client for the AgentFinder service
# (see github/agentfinder). It powers the staff-gated /agentfinder demo view.
#
# The AgentFinder service exposes:
#   - POST /api/v1/search       — semantic search across a multi-source catalog
#   - GET  /api/v1/agents       — paginated browse without ranking
#   - GET  /api/v1/types        — known mediaType values
#
# Its native response shape (see internal/domain/entry.go upstream) is a
# CatalogEntry with fields like {identifier, displayName, mediaType, url,
# description, tags}. To minimise UI churn during the demo, this client maps
# those entries into the same {servers, metadata} envelope that the existing
# UI (cloned from McpRegistry) already consumes. This is intentionally a
# demo-only adapter and is not production-ready.
module AgentFinder
  class RestApiClient
    LIMIT = T.let(30, Integer)
    OPEN_TIMEOUT = T.let(5, Integer)
    READ_TIMEOUT = T.let(15, Integer)
    # AgentFinder caps /api/v1/agents pageSize at 100, so we page upstream to
    # build a larger working pool.
    UPSTREAM_PAGE_SIZE = T.let(100, Integer)
    # Hard upper bound on how many entries we'll pull from upstream when
    # building the landing-view pool. Keeps demo behaviour predictable if the
    # catalog grows.
    MAX_POOL = T.let(2_000, Integer)
    # Entries whose description is shorter than this (after stripping) are
    # dropped from list/search results — they're usually placeholder cards
    # with no useful content for the demo.
    MIN_DESCRIPTION_LENGTH = T.let(20, Integer)

    class AgentNotFoundError < StandardError; end

    sig do
      params(
        page: Integer,
        per_page: Integer,
        search: T.nilable(String),
        types: T::Array[String]
      ).returns(T::Hash[String, T.untyped])
    end
    def self.fetch_servers(page: 1, per_page: LIMIT, search: nil, types: [])
      if search.present?
        search_agents(query: search, page: page, per_page: per_page, types: types)
      else
        list_agents(page: page, per_page: per_page, types: types)
      end
    rescue StandardError => e
      Rails.logger.error "AgentFinder list failed: #{e.message}"
      empty_response
    end

    # Fetches the catalog's known resource types and their total counts from
    # /api/v1/types. Returns a normalised array of {label, media_type, count}
    # hashes the UI uses to populate the resource-type filter.
    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_types
      uri = URI("#{GitHub.agent_finder_url}/api/v1/types")
      response = http_get(T.cast(uri, URI::HTTP))
      return [] unless response.code == "200"

      raw = JSON.parse(T.must(response.body))
      Array(raw["types"]).filter_map do |type|
        label = type["label"].to_s
        next if label.empty?

        {
          "label" => label,
          "media_type" => type["mediaType"].to_s,
          "count" => type["count"].to_i
        }
      end
    rescue StandardError => e
      Rails.logger.error "AgentFinder types failed: #{e.message}"
      []
    end

    sig do
      params(
        query: String,
        page: Integer,
        per_page: Integer,
        types: T::Array[String]
      ).returns(T::Hash[String, T.untyped])
    end
    def self.search_agents(query:, page: 1, per_page: LIMIT, types: [])
      # /api/v1/search returns the top-K ranked results in a single shot
      # (no native pagination). To keep the existing page-based UI working we
      # request enough results to cover the current page and then slice.
      top_k = [(page * per_page), 100].min
      uri = URI("#{GitHub.agent_finder_url}/api/v1/search")
      body = JSON.dump({ "query" => query, "topK" => top_k })
      response = http_post(T.cast(uri, URI::HTTP), body)

      return empty_response unless response.code == "200"

      raw = JSON.parse(T.must(response.body))
      entries = Array(raw["results"]).select { |e| viable_entry?(e) }
      entries = filter_by_types(entries, types)
      total = entries.length

      offset = (page - 1) * per_page
      page_entries = entries[offset, per_page] || []

      build_response(page_entries, total: total, page: page, per_page: per_page)
    end

    sig { params(page: Integer, per_page: Integer, types: T::Array[String]).returns(T::Hash[String, T.untyped]) }
    def self.list_agents(page: 1, per_page: LIMIT, types: [])
      # AgentFinder's /agents endpoint returns results in catalog order. For
      # the landing view we want the most-popular entries first across all
      # mediaTypes, so we page upstream to build a larger working pool,
      # filter, sort by metadata.likes desc, then paginate client-side. Type
      # filtering happens here, before pagination, so page counts stay
      # accurate across the full pool even though the upstream service cannot
      # filter by type.
      entries = fetch_all_agents.select { |e| viable_entry?(e) }
      entries = filter_by_types(entries, types)
      total = entries.length

      sorted = entries.sort_by { |e| -likes_for(e) }

      offset = (page - 1) * per_page
      page_entries = sorted[offset, per_page] || []

      build_response(page_entries, total: total, page: page, per_page: per_page)
    end

    # Pages /api/v1/agents up to MAX_POOL entries (or until the upstream total
    # is reached). Stops early on any non-200 response.
    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_all_agents
      collected = T.let([], T::Array[T::Hash[String, T.untyped]])
      offset = 0
      loop do
        uri = URI("#{GitHub.agent_finder_url}/api/v1/agents")
        uri.query = URI.encode_www_form(offset: offset, pageSize: UPSTREAM_PAGE_SIZE)
        response = http_get(T.cast(uri, URI::HTTP))
        break unless response.code == "200"

        raw = JSON.parse(T.must(response.body))
        batch = Array(raw["results"])
        break if batch.empty?

        collected.concat(batch)
        upstream_total = raw["total"].to_i
        break if collected.length >= MAX_POOL
        break if upstream_total.positive? && collected.length >= upstream_total

        offset += UPSTREAM_PAGE_SIZE
      end
      collected
    end

    # AgentFinder has no per-identifier GET endpoint. For the demo show view we
    # fall back to scanning the agents pool. The Ruby controller will treat
    # this as best-effort.
    sig { params(identifier: String).returns(T::Hash[String, T.untyped]) }
    def self.fetch_agent_by_identifier(identifier)
      entries = fetch_all_agents
      match = entries.find { |e| e["identifier"] == identifier }
      raise AgentNotFoundError, "Agent not found" unless match

      transform_entry(match)
    rescue AgentNotFoundError
      raise
    rescue StandardError => e
      Rails.logger.error "AgentFinder show failed: #{e.message}"
      raise AgentNotFoundError, "Agent not found"
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def self.empty_response
      {
        "servers" => [],
        "metadata" => { "count" => 0, "total" => 0, "total_pages" => 0 }
      }
    end

    sig do
      params(
        entries: T::Array[T::Hash[String, T.untyped]],
        total: Integer,
        page: Integer,
        per_page: Integer
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build_response(entries, total:, page:, per_page:)
      total_pages = per_page.positive? ? (total.to_f / per_page).ceil : 0
      servers = entries.map { |e| transform_entry(e) }
      {
        "servers" => servers,
        "metadata" => {
          "count" => servers.length,
          "total" => total,
          "total_pages" => total_pages
        }
      }
    end

    # Entries with no/very short descriptions are uninteresting demo cards and
    # are filtered out before pagination so page counts stay accurate.
    sig { params(entry: T::Hash[String, T.untyped]).returns(T::Boolean) }
    def self.viable_entry?(entry)
      entry["description"].to_s.strip.length >= MIN_DESCRIPTION_LENGTH
    end

    # Narrows entries to the selected resource type labels. Matching is done on
    # the human-readable label (via media_type_label) so it stays consistent
    # with the `extension_type` the UI displays and the labels returned by
    # fetch_types. A blank/empty selection is a no-op.
    sig do
      params(
        entries: T::Array[T::Hash[String, T.untyped]],
        types: T::Array[String]
      ).returns(T::Array[T::Hash[String, T.untyped]])
    end
    def self.filter_by_types(entries, types)
      selected = types.map { |type| type.to_s.strip.downcase }.reject(&:empty?)
      return entries if selected.empty?

      entries.select do |entry|
        label = media_type_label(entry["mediaType"].to_s)
        label.present? && selected.include?(label.downcase)
      end
    end

    # Maps an AgentFinder CatalogEntry / SearchResult into the BaseServer shape
    # the existing React UI expects. Only fields used by the cards are populated.
    sig { params(entry: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def self.transform_entry(entry)
      identifier = entry["identifier"].to_s
      display_name = entry["displayName"].presence || identifier
      description = entry["description"].to_s
      media_type = entry["mediaType"].to_s
      likes = likes_for(entry)

      base = {
        "id" => identifier,
        "name" => identifier,
        "full_name" => identifier,
        "api_name" => identifier,
        "display_name" => display_name,
        "description" => description,
        "url" => entry["url"].to_s,
        "created_at" => entry["updatedAt"].to_s,
        "updated_at" => entry["updatedAt"].to_s,
        "topics" => Array(entry["tags"]),
        "extension_type" => media_type_label(media_type),
        "uses_custom_opengraph_image" => false
      }
      # Surface metadata.likes (e.g. Hugging Face Space likes) in the same
      # slot the UI already renders as a star count, so the cards get a
      # popularity signal when one is available.
      base["stargazer_count"] = likes if likes.positive?
      base
    end

    sig { params(entry: T::Hash[String, T.untyped]).returns(Integer) }
    def self.likes_for(entry)
      metadata = entry["metadata"]
      return 0 unless metadata.is_a?(Hash)
      metadata["likes"].to_i
    end

    sig { params(media_type: String).returns(T.nilable(String)) }
    def self.media_type_label(media_type)
      case media_type
      when "application/mcp-server+json" then "MCP server"
      when "application/agent+json" then "Agent"
      when "application/a2a-agent-card+json" then "A2A agent"
      when "application/ai-skill" then "Skill"
      when "application/canvas+json" then "Canvas"
      when "" then nil
      else media_type
      end
    end

    sig { params(uri: URI::HTTP).returns(Net::HTTPResponse) }
    def self.http_get(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Accept"] = "application/json"
      http.request(req)
    end

    sig { params(uri: URI::HTTP, body: String).returns(Net::HTTPResponse) }
    def self.http_post(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = body
      http.request(req)
    end
  end
end
