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

  LIMIT = 30
  IO_GITHUB_PREFIX = "io.github.".freeze

  def index
    context_region_preset :mcp

    # Support both 'search' (v0.1 API) and 'q' (v0 API) parameters
    search = params[:search].presence || params[:q].presence

    # Handle page-based pagination
    page = params[:page].present? ? params[:page].to_i : 1

    # Use a larger limit when v0.1 API is disabled to show all servers on one page
    per_page = FeatureFlag.vexi.enabled?(:mcp_registry_oss_v0_1_api, default: false) ? LIMIT : 100

    servers_data = McpRegistry::RestApiClient.fetch_servers(page: page, per_page: per_page, search: search)

    enriched_servers_data = servers_data.merge(
      "servers" => servers_data.fetch("servers", []).map { |server| decorate_server_data(server) }
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
    server_data = fetch_server_data(params[:name]).with_indifferent_access

    readme_content = server_data.dig("repository", "readme")

    # If README is not in API response, fall back to Repository lookup
    if readme_content.blank?
      repo_id = server_data["repo_id"]
      @repo = Repositories.domain.by_id(repo_id.to_i)
      readme_content = get_readme_markdown(@repo) if @repo.present?
    elsif readme_content.is_a?(String)
      # README is in API response, process it
      repo_url = server_data.dig("repository", "url") || server_data["url"]
      name_with_owner = server_data["name_with_owner"]
      default_branch = server_data.dig("repository", "default_branch")

      if repo_url.present?
        rewritten_content = rewrite_readme_assets(readme_content, repo_url, name_with_owner, default_branch)
      else
        rewritten_content = readme_content
      end

      context = {
        force_show_snippet_buttons: true,
        gfm: true,
      }
      parsed_readme = GitHub::Goomba::MarkdownPipeline.to_html(rewritten_content, context, nil, cache_settings: { use_cache: true })
      server_data["repository"] ||= {}
      server_data["repository"]["parsed_readme"] = parsed_readme
    end

    server_data = decorate_server_data(server_data)

    mcp_name = server_data["display_name"]
    vanity_name = server_data["name"]

    set_nav_breadcrumb(ContextRegion::BasicCrumb.new(nil,
      label: mcp_name,
      parent: ContextRegion::McpCrumb.new)
    )

    title = "MCP Registry | #{mcp_name}"
    description = "A faster, safer way to build with AI: the GitHub MCP Registry centralizes MCP servers for effortless discovery, integration, and open collaboration."

    respond_with_react(
      payload: McpServerPayload.new(
        server_data: server_data,
        readme_content: readme_content,
        is_logged_in: logged_in?
      ),
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

    def initialize(server_data:, readme_content:, is_logged_in: false)
      @server_data = server_data
      @readme_content = readme_content
      @is_logged_in = is_logged_in
    end

    def payload
      {
        server_data: @server_data.merge(
          readme_content: @readme_content
        ),
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

  # Rewrites local asset references in markdown content to absolute URLs.
  #
  # @param markdown [String] The markdown content to rewrite.
  # @param repo_url [String] The repository URL (e.g., "https://github.com/owner/repo").
  # @param name_with_owner [String, nil] Optional name_with_owner to avoid URL parsing.
  # @param default_branch [String, nil] The default branch of the repository from the API response.
  # @return [String] The markdown with rewritten asset URLs, or the original markdown if rewriting fails.
  def rewrite_readme_assets(markdown, repo_url, name_with_owner = nil, default_branch = nil)
    return markdown unless markdown.is_a?(String) && !markdown.empty?
    return markdown unless repo_url.present?

    # Prefer using name_with_owner if provided, otherwise extract from URL
    if name_with_owner.present?
      name_with_owner_string = name_with_owner
    else
      # Extract owner and repo from GitHub URL (e.g., "https://github.com/owner/repo")
      match = repo_url.match(%r{github\.com/([^/]+)/([^/]+)/?\z})
      return markdown unless match

      display_login = match[1]
      repo_name = match[2]
      name_with_owner_string = "#{display_login}/#{repo_name}"
    end

    # If default_branch is not provided in API response, fall back to repository lookup
    if default_branch.blank?
      repo = Repository.with_name_with_owner(name_with_owner_string)
      return markdown unless repo

      base_url = build_raw_content_base_url(repo)
    else
      # Use the default_branch from API response to avoid repository lookup
      base_host = GitHub.urls.raw_host_url.presence || "https://raw.githubusercontent.com"
      parts = name_with_owner_string.split("/")
      base_url = "#{base_host}/#{parts[0]}/#{parts[1]}/#{default_branch}"
    end

    rewrite_local_image_refs_in_markdown(markdown, base_url)
  end

  # Builds the base URL for raw content from a repository.
  #
  # @param repo [Repository] The repository object.
  # @return [String] The base URL for raw content (e.g., "https://raw.githubusercontent.com/owner/repo/main").
  def build_raw_content_base_url(repo)
    base_host = GitHub.urls.raw_host_url.presence || "https://raw.githubusercontent.com"
    "#{base_host}/#{repo.owner_display_login}/#{repo.name}/#{repo.default_branch}"
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

  def sanitized_display_name(name, fallback)
    trimmed = name.to_s.strip
    return format_mcp_name(fallback) if trimmed.blank?

    return format_mcp_name(fallback) if trimmed.start_with?(IO_GITHUB_PREFIX)

    trimmed
  end
end
