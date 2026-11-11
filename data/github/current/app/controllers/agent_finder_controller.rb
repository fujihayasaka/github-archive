# typed: true
# frozen_string_literal: true

require "react_payload"
require "agent_finder/rest_api_client"

# AgentFinderController serves the /agentfinder demo route.
#
# This view is a clone of {McpRegistryController} (which backs github.com/mcp).
# It is intentionally gated behind the :agent_finder_ui feature flag so it is
# only reachable by staff during the demo phase. The view will be redesigned
# before any public release and is never exposed to customers in its current
# form. Data is fetched from the AgentFinder service via
# {AgentFinder::RestApiClient}; the response is adapted into the
# MCP-Registry-shaped payload the cloned React UI still consumes.
class AgentFinderController < ApplicationController
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

  LIMIT = 30
  IO_GITHUB_PREFIX = "io.github.".freeze

  def index
    context_region_preset :agent_finder

    # Support both 'search' (v0.1 API) and 'q' (v0 API) parameters
    search = params[:search].presence || params[:q].presence

    # Handle page-based pagination
    page = params[:page].present? ? params[:page].to_i : 1
    per_page = LIMIT

    # Resource type filter. Applied server-side (here in the monolith adapter,
    # which already materialises and paginates the catalog pool) so filtering
    # stays correct across pages. Accepts a comma-separated list of type
    # labels, e.g. ?type=MCP%20server,Skill.
    types = params[:type].to_s.split(",").map(&:strip).reject(&:blank?)

    servers_data = AgentFinder::RestApiClient.fetch_servers(
      page: page,
      per_page: per_page,
      search: search,
      types: types
    )
    types_data = AgentFinder::RestApiClient.fetch_types

    enriched_servers_data = servers_data.merge(
      "servers" => servers_data.fetch("servers", []).map { |server| omit_readme(server) }
    )

    title = "Agent Finder"
    description = "Agent Finder: a faster, safer way to build with AI."

    respond_with_react(
      payload: AgentFinderPayload.new(servers_data: enriched_servers_data, types_data: types_data),
      title: title,
      page_data: {
        description: description,
        page_type: "marketing",
        revenue_play: "AI",
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
    # AgentFinder identifiers (e.g. URNs) are passed through verbatim. We use
    # the wildcard *name route segment as the lookup key.
    server_data = AgentFinder::RestApiClient.fetch_agent_by_identifier(params[:name].to_s).with_indifferent_access

    mcp_name = server_data["display_name"]

    set_nav_breadcrumb(ContextRegion::BasicCrumb.new(nil,
      label: mcp_name,
      parent: ContextRegion::AgentFinderCrumb.new)
    )

    title = "Agent Finder | #{mcp_name}"
    description = "Agent Finder: a faster, safer way to build with AI."

    respond_with_react(
      payload: AgentFinderServerPayload.new(
        server_data: server_data,
        is_logged_in: logged_in?
      ),
      title: title,
      page_data: {
        description: description,
        page_type: "marketing",
        revenue_play: "AI",
        richweb: {
          description: description,
          image: image_path("modules/site/social-cards/github-mcp-registry.png"),
          title: title,
          url: T.must(request).original_url
        },
      },
    )
  rescue AgentFinder::RestApiClient::AgentNotFoundError => e
    Rails.logger.info "Agent Finder extension not found: #{e.message}"
    render_404
  end

  private

  # We intentionally do NOT define `#resource_for_conditional_access`: there is
  # no domain resource (Repository / Issue / etc.) in scope for this view, so
  # the framework's default behaviour — dispatching back to this controller's
  # `#target_for_conditional_access` — is correct. See
  # {ApplicationController::ConditionalAccessDependency#perform_conditional_access_checks}.
  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  class AgentFinderPayload < ReactPayload::Base
    def route_id
      "agentFinderRoute"
    end

    def initialize(servers_data:, types_data: [])
      @servers_data = servers_data
      @types_data = types_data
    end

    def payload
      {
        serversData: @servers_data,
        typesData: @types_data,
      }
    end
  end

  class AgentFinderServerPayload < ReactPayload::Base
    def route_id
      "agentDetailsRoute"
    end

    def initialize(server_data:, is_logged_in: false)
      @server_data = server_data
      @is_logged_in = is_logged_in
    end

    def payload
      {
        server_data: @server_data,
        isLoggedIn: @is_logged_in,
      }
    end
  end

  # Gets the raw markdown content for the repository README, rewriting local image references to absolute raw URLs.
  def get_readme_markdown(repo)
    return nil unless repo&.preferred_readme

    # If we have the raw markdown data for the blob, rewrite local image refs so they point to absolute raw URLs.
    raw_markdown = repo.preferred_readme.data

    if raw_markdown.is_a?(String) && !raw_markdown.empty?
      # Build base URLs for raw content (images) and blob content (document links)
      raw_base_url = build_raw_content_base_url(repo)
      blob_base_url = build_blob_content_base_url(repo)

      rewritten = rewrite_local_refs_in_markdown(raw_markdown, raw_base_url, blob_base_url)

      # Pass rewritten markdown into the markup pipeline via the :data context so the blob rendering uses our modified content.
      html, _ = helpers.format_blob_with_result(repo.preferred_readme, data: rewritten)
    else
      # Fall back to formatting the original blob if we don't have raw data.
      html, _ = helpers.format_blob_with_result(repo.preferred_readme)
    end

    html
  end

  # Replace relative markdown image and link references with absolute URLs.
  # Images are rewritten to raw URLs (for direct rendering), while document links are rewritten to blob URLs (for proper GitHub viewing).
  # Matches inline images and links: `![alt](path "title")` and `[text](path "title")`.
  # Examples:
  #   ![Alt text](docs/images/foo.png) => ![Alt text](https://raw.githubusercontent.com/owner/repo/main/docs/images/foo.png)
  #   [Docs](docs/guide.md) => [Docs](https://github.com/owner/repo/blob/main/docs/guide.md)
  #
  # NOTE: This method is ONLY used for the fallback path when README is not available from the
  # mcp-registry API (which handles its own URL transformations server-side). When fetching README
  # directly from the repository, we still need to transform local refs to absolute URLs.
  #
  # @param markdown [String] The markdown content to rewrite.
  # @param raw_base_url [String] The base URL for raw content (used for images).
  # @param blob_base_url [String, nil] The base URL for blob content (used for document links). Falls back to raw_base_url if nil.
  def rewrite_local_refs_in_markdown(markdown, raw_base_url, blob_base_url = nil)
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
          # Use raw_base_url for images, blob_base_url for document links
          # This ensures images render correctly while document links go to GitHub's blob view
          is_image = prefix == "!"
          effective_base_url = if is_image
            raw_base_url
          else
            blob_base_url || raw_base_url
          end

          begin
            # Encode each path segment (so we don't percent-encode the separators) and join with Addressable to normalize
            safe_path = normalized.split("/").map { |seg| Addressable::URI.encode_component(seg, Addressable::URI::CharacterClasses::PATH) }.join("/")

            base_for_join = effective_base_url.end_with?("/") ? effective_base_url : "#{effective_base_url}/"
            absolute = Addressable::URI.parse(base_for_join).join(safe_path).normalize.to_s

            "#{prefix}[#{label}](#{absolute}#{title_part})"
          rescue Addressable::URI::InvalidURIError
            # Fall back to simple concatenation if Addressable fails, preserving effective_base_url behavior
            "#{prefix}[#{label}](#{effective_base_url}/#{normalized}#{title_part})"
          end
        end
      end
    end
  end

  # Staff-only demo gate. When :agent_finder_ui is disabled for the actor
  # (the default in production), the view is invisible — the controller renders
  # the standard 404 page so the route cannot be discovered.
  def require_feature_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:agent_finder_ui, current_user, default: false)
  end

  # Builds the base URL for raw content from a repository.
  #
  # @param repo [Repository] The repository object.
  # @return [String] The base URL for raw content (e.g., "https://raw.githubusercontent.com/owner/repo/main").
  def build_raw_content_base_url(repo)
    base_host = GitHub.urls.raw_host_url.presence || "https://raw.githubusercontent.com"
    "#{base_host}/#{repo.owner_display_login}/#{repo.name}/#{repo.default_branch}"
  end

  # Builds the base URL for blob content from a repository (for viewing files in GitHub UI).
  #
  # @param repo [Repository] The repository object.
  # @return [String] The base URL for blob content (e.g., "https://github.com/owner/repo/blob/main").
  def build_blob_content_base_url(repo)
    base_host = GitHub.urls.url.presence || "https://github.com"
    "#{base_host}/#{repo.owner_display_login}/#{repo.name}/blob/#{repo.default_branch}"
  end

  def mcp_display_name(data)
    data = data.with_indifferent_access

    display_name = data.dig(:display_name).to_s.strip
    return sanitized_display_name(display_name, data[:name]) if display_name.present?

    raw_display_name = data.dig(:raw_data, :"x-github", :display_name).to_s.strip
    return sanitized_display_name(raw_display_name, data[:name]) if raw_display_name.present?

    format_mcp_name(data[:name])
  end

  def format_mcp_name(mcp_name)
    return "" if mcp_name.blank?

    # Extract repo name from format: io.github.<username>/<repo-name>
    parts = mcp_name.split("/")
    return mcp_name if parts.length < 2

    parts[1].squish.titleize(keep_id_suffix: true).gsub("Github", "GitHub").gsub("Mcp", "MCP")
  end

  def vanity_mcp_name(name)
    trimmed_name = name.to_s.strip
    return "" if trimmed_name.blank?

    if trimmed_name.start_with?(IO_GITHUB_PREFIX)
      return trimmed_name.delete_prefix(IO_GITHUB_PREFIX)
    end

    trimmed_name
  end

  def canonical_mcp_name(name)
    trimmed_name = name.to_s.strip
    return "" if trimmed_name.blank?

    return trimmed_name if trimmed_name.start_with?(IO_GITHUB_PREFIX)

    namespace_segment, repo = trimmed_name.split("/", 2)
    return trimmed_name if repo.blank?

    "#{IO_GITHUB_PREFIX}#{namespace_segment}/#{repo}"
  end

  def fetch_server_data(requested_name)
    canonical_name = canonical_mcp_name(requested_name)
    canonical_name = requested_name.to_s.strip if canonical_name.blank?
    McpRegistry::RestApiClient.fetch_server_by_name(canonical_name)
  rescue McpRegistry::RestApiClient::ServerNotFoundError
    raise if canonical_name == requested_name.to_s.strip

    McpRegistry::RestApiClient.fetch_server_by_name(requested_name)
  end

  def decorate_server_data(server_hash)
    data = server_hash.with_indifferent_access
    raw_name = data[:name].to_s

    canonical_name = canonical_mcp_name(raw_name)
    canonical_name = raw_name if canonical_name.blank?

    vanity_name = vanity_mcp_name(canonical_name.presence || raw_name)
    vanity_name = raw_name if vanity_name.blank?

    data.merge(
      "display_name" => mcp_display_name(data),
      "name" => vanity_name,
      "full_name" => canonical_name,
      "api_name" => raw_name
    )
  end

  def omit_readme(server_hash)
    if server_hash["repository"].is_a?(Hash)
      server_hash.merge(
        "repository" => server_hash["repository"].except("readme", :readme)
      )
    else
      server_hash
    end
  end

  def sanitized_display_name(name, fallback)
    trimmed = name.to_s.strip
    return format_mcp_name(fallback) if trimmed.blank?

    return format_mcp_name(fallback) if trimmed.start_with?(IO_GITHUB_PREFIX)

    trimmed
  end
end
