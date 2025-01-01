# typed: true
# frozen_string_literal: true

require "react_payload"
require "mcp_registry/rest_api_client"

class McpRegistryController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories

  before_action :require_feature_enabled

  stylesheet_bundle :code

  def index
    context_region_preset :mcp

    cursor = params[:cursor]
    limit = (params[:limit] || 100).to_i
    q = params[:q]

    servers_data = McpRegistry::RestApiClient.fetch_servers(cursor: cursor, limit: limit, q: q)

    enriched_servers_data = servers_data.merge(
      "servers" => servers_data["servers"].map do |server|
        server.merge("display_name" => mcp_display_name(server))
      end
    )

    title = "MCP Registry"
    description = "A faster, safer way to build with AI: the GitHub MCP Registry centralizes MCP servers for effortless discovery, integration, and open collaboration."

    respond_with_react(
      payload: McpRegistryPayload.new(servers_data: enriched_servers_data),
      title: title,
      page_data: {
        description: description,
        richweb: {
          description: description,
          image: image_path("modules/site/social-cards/github-mcp-registry.png"),
          title: title,
          url: T.must(request).original_url
        },
      },
    )
  end

  def show
    server_data = McpRegistry::RestApiClient.fetch_server_by_name(params[:name])

    repo_id = server_data["repo_id"]
    @repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(repo_id.to_i)
    else
      Repository.find_by(id: repo_id)
    end
    repo_readme_markdown = get_readme_markdown(@repo) if @repo.present?

    mcp_name = mcp_display_name(server_data)

    enriched_server_data = server_data.merge(
      "display_name" => mcp_name
    )

    set_nav_breadcrumb(ContextRegion::BasicCrumb.new(nil,
      label: mcp_name,
      parent: ContextRegion::McpCrumb.new)
    )

    title = "MCP Registry | #{mcp_name}"
    description = "A faster, safer way to build with AI: the GitHub MCP Registry centralizes MCP servers for effortless discovery, integration, and open collaboration."

    respond_with_react(
      payload: McpServerPayload.new(server_data: enriched_server_data, readme_markdown: repo_readme_markdown),
      title: title,
      page_data: {
        description: description,
        richweb: {
          description: description,
          image: image_path("modules/site/social-cards/github-mcp-registry.png"),
          title: title,
          url: T.must(request).original_url
        },
      },
    )
  rescue McpRegistry::RestApiClient::ServerNotFoundError => e
    Rails.logger.info "MCP Registry server not found: #{e.message}"
    render_404
  end

  private

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  class McpRegistryPayload < ReactPayload::Base
    def route_id
      "mcpRegistryRoute"
    end

    def initialize(servers_data:)
      @servers_data = servers_data
    end

    def payload
      {
        serversData: @servers_data,
      }
    end
  end

  class McpServerPayload < ReactPayload::Base
    def route_id
      "mcpDetailsRoute"
    end

    def initialize(server_data:, readme_markdown:)
      @server_data = server_data
      @readme_markdown = readme_markdown
    end

    def payload
      {
        server_data: @server_data.merge(
          readme_content: @readme_markdown
        ),
      }
    end
  end

  # Gets the raw markdown content for the repository README, rewriting local image references to absolute raw URLs.
  def get_readme_markdown(repo)
    return nil unless repo&.preferred_readme

    # If we have the raw markdown data for the blob, rewrite local image refs so they point to absolute raw URLs.
    raw_markdown = repo.preferred_readme.data

    if raw_markdown.is_a?(String) && !raw_markdown.empty?
      # Build a sensible base raw URL: prefer the configured raw host URL, fallback to raw.githubusercontent.com style.
      base_host = GitHub.urls.raw_host_url.presence || "https://raw.githubusercontent.com"
      base_url = "#{base_host}/#{repo.owner_display_login}/#{repo.name}/#{repo.default_branch}"

      rewritten = rewrite_local_image_refs_in_markdown(raw_markdown, base_url)

      # Pass rewritten markdown into the markup pipeline via the :data context so the blob rendering uses our modified content.
      html, _ = helpers.format_blob_with_result(repo.preferred_readme, data: rewritten)
    else
      # Fall back to formatting the original blob if we don't have raw data.
      html, _ = helpers.format_blob_with_result(repo.preferred_readme)
    end

    html
  end

  # Replace relative markdown image and link references with absolute raw URLs based on a base raw URL.
  # Matches inline images and links: `![alt](path "title")` and `[text](path "title")`.
  # Examples:
  #   ![Alt text](docs/images/foo.png) => ![Alt text](https://raw.githubusercontent.com/owner/repo/main/docs/images/foo.png)
  #   [Docs](docs/guide.md) => [Docs](https://raw.githubusercontent.com/owner/repo/main/docs/guide.md)
  def rewrite_local_image_refs_in_markdown(markdown, base_url)
    return markdown unless markdown.is_a?(String) && !markdown.empty?

    # Safe regex to match inline markdown images and links: optional '!' then [text](url "optional title")
    # - group 1: optional leading '!' (image marker)
    # - group 2: link text / alt
    # - group 3: url
    # - group 4: optional title portion including leading whitespace
    link_re = /(!)?\[([^\]]*)\]\(\s*([^\s)]+)(\s+(?:"[^"]*"|'[^']*'|[^)\r\n]+))?\s*\)/

    markdown.gsub(link_re) do
      full_match = Regexp.last_match(0)
      prefix = (Regexp.last_match(1) || "")
      label = (Regexp.last_match(2) || "")
      url = Regexp.last_match(3).to_s
      title_part = Regexp.last_match(4) || ""

      # Leave protocol-relative and any URI with a scheme (e.g. http:, https:, mailto:, data:) untouched
      if url.start_with?("//") || url =~ /\A[A-Za-z][A-Za-z0-9+\.\-]*:/
        full_match
      else
        # Normalize leading './' or '/'
        normalized = url.sub(%r{\A\./}, "").sub(%r{\A/}, "")

        # Allowlist characters in the normalized path and disallow `..` segments.
        allowed_re = /\A[0-9A-Za-z._\-\/%]+\z/
        if normalized.include?("..") || !allowed_re.match?(normalized)
          full_match
        else
          begin
            # Encode each path segment (so we don't percent-encode the separators) and join with Addressable to normalize
            safe_path = normalized.split("/").map { |seg| Addressable::URI.encode_component(seg, Addressable::URI::CharacterClasses::PATH) }.join("/")
            base_for_join = base_url.end_with?("/") ? base_url : "#{base_url}/"
            absolute = Addressable::URI.parse(base_for_join).join(safe_path).normalize.to_s

            "#{prefix}[#{label}](#{absolute}#{title_part})"
          rescue Addressable::URI::InvalidURIError
            # Fall back to simple concatenation if Addressable fails
            "#{prefix}[#{label}](#{base_url}/#{normalized}#{title_part})"
          end
        end
      end
    end
  end

  def require_feature_enabled
    render_404 unless user_or_global_feature_enabled?(:mcp_registry_v1)
  end

  def mcp_display_name(data)
    data = data.with_indifferent_access

    display_name = data.dig(:display_name).to_s.strip
    return display_name if display_name.present?

    raw_display_name = data.dig(:raw_data, :"x-github", :display_name).to_s.strip
    return raw_display_name if raw_display_name.present?

    format_mcp_name(data[:name])
  end

  def format_mcp_name(mcp_name)
    return "" if mcp_name.blank?

    # Extract repo name from format: io.github.<username>/<repo-name>
    parts = mcp_name.split("/")
    return mcp_name if parts.length < 2

    parts[1].squish.titleize(keep_id_suffix: true).gsub("Github", "GitHub").gsub("Mcp", "MCP")
  end
end
