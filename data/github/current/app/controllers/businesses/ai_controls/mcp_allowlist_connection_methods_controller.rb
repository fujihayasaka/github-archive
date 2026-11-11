# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_allowlist_client"

class Businesses::AiControls::McpAllowlistConnectionMethodsController < Businesses::BusinessController
  include Businesses::CopilotShared
  include Businesses::AiControls::McpAllowlistShared

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AiControls::McpAllowlistConnectionMethodsController#create",
  ].freeze

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ai_controls_read_required
  before_action :ensure_allowlist_feature_flag_enabled

  sig { void }
  def index
    render_connection_methods
  end

  sig { void }
  def create
    render_connection_methods
  end

  private

  sig { void }
  def render_connection_methods
    entries = build_connection_method_entries
    respond_to do |format|
      format.any(:html, :html_fragment) do
        render partial: "businesses/ai_controls/mcp/connection_methods",
               locals: { entries: entries },
               layout: false,
               formats: [:html, :html_fragment]
      end
    end
  end

  # Builds the entries array for the connection_methods partial.
  # Dispatches to the appropriate method based on the flow (edit vs create).
  # When editing an allowlist and adding a NEW server that isn't associated yet,
  # the API returns 404. In that case we fall back to catalog params so the
  # checkboxes still render from the catalog data sent by the frontend.
  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def build_connection_method_entries
    allowlist_id = params[:allowlist_id].to_s.strip
    server_id = params[:server_id].to_s.strip

    if allowlist_id.present? && server_id.present?
      api_entries = fetch_entries_from_api(allowlist_id, server_id)

      if api_entries.nil?
        # nil means server not found in allowlist (404) — fall back to catalog params only.
        build_entries_from_catalog_params
      else
        # API returned entries (possibly empty). Merge with catalog params so that
        # connection methods not yet tracked by the registry (e.g. remotes from
        # version_metadata) still appear as selectable checkboxes.
        catalog_entries = build_entries_from_catalog_params
        merge_api_and_catalog_entries(api_entries, catalog_entries)
      end
    else
      build_entries_from_catalog_params
    end
  end

  # Edit flow: fetches existing entries from the MCP Registry API.
  # Returns nil on 404 (server not yet associated with this allowlist) so the
  # caller can fall back to catalog params. Returns [] for a successful response
  # with no entries (the caller merges these with catalog entries so that entry
  # types not tracked by the registry still appear as selectable checkboxes).
  # Other API errors return [] and are logged as warnings.
  sig { params(allowlist_id: String, server_id: String).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
  def fetch_entries_from_api(allowlist_id, server_id)
    result = McpRegistry::EnterpriseAllowlistClient.list_server_entries(
      enterprise_id: this_business.id.to_s,
      allowlist_id: allowlist_id,
      server_id: server_id,
      token: mcp_registry_token,
    )
    Array(result["entries"])
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    if e.status == 404
      Rails.logger.info("[MCP ConnectionMethods] Server #{server_id} not found in allowlist #{allowlist_id}, falling back to catalog params")
      nil
    else
      Rails.logger.warn("[MCP ConnectionMethods] Failed to fetch entries for server=#{server_id} allowlist=#{allowlist_id}: #{e.status} #{e.message}")
      []
    end
  end

  # Create flow: builds entries from catalog data passed as JSON params.
  # Only permitted fields are extracted from the parsed JSON.
  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def build_entries_from_catalog_params
    entries = T.let([], T::Array[T::Hash[String, T.untyped]])
    parse_catalog_json(:remotes, "remote", entries) do |remote|
      url = (remote["url"] || remote["URL"]).to_s
      transport_type = (remote["type"] || remote["transport_type"] || "sse").to_s
      next if url.blank?
      { "display_name" => "#{transport_type}: #{url}", "remote_url" => url, "remote_transport_type" => transport_type }
    end
    parse_catalog_json(:packages, "package", entries) do |pkg|
      pkg_name = (pkg["name"] || pkg["package_name"] || pkg["identifier"]).to_s
      registry = (pkg["registry_name"] || pkg["registry"] || pkg["registryType"]).to_s
      next if pkg_name.blank?
      display_name = registry.present? ? "#{registry}: #{pkg_name}" : pkg_name
      { "display_name" => display_name }
    end
    entries
  end

  # Parses a JSON param, iterates items, and appends entries with display names
  # and optional extra fields returned by the block. Block should return a Hash
  # with at least "display_name", or nil/next to skip an item. Extra keys like
  # "remote_url" and "remote_transport_type" are merged into the entry.
  sig do
    params(
      param_key: Symbol,
      entry_type: String,
      entries: T::Array[T::Hash[String, T.untyped]],
      blk: T.proc.params(item: T::Hash[String, T.untyped]).returns(T.nilable(T.any(String, T::Hash[String, T.untyped]))),
    ).void
  end
  def parse_catalog_json(param_key, entry_type, entries, &blk)
    return unless params[param_key].present?

    items = JSON.parse(params[param_key])
    offset = entries.length
    Array(items).each_with_index do |item, i|
      next unless item.is_a?(Hash)
      result = blk.call(item)
      next if result.nil?

      # Support both String (display_name only) and Hash (display_name + extra fields)
      if result.is_a?(Hash)
        display_name = result["display_name"]
        next if display_name.blank?
        entry = { "id" => offset + i + 1, "type" => entry_type, "display_name" => display_name, "selected" => true }
        entry.merge!(result.except("display_name"))
        entries << entry
      else
        next if result.blank?
        entries << { "id" => offset + i + 1, "type" => entry_type, "display_name" => result, "selected" => true }
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.warn("[MCP ConnectionMethods] Failed to parse #{param_key} JSON: #{e.message}")
  end

  # Merges API-sourced entries (with real IDs) with catalog-sourced entries.
  # API entries take priority. Catalog entries that don't match any API entry
  # by display_name (or by compound URL key for URL-based remotes) are appended
  # so they appear as selectable checkboxes.
  sig { params(api_entries: T::Array[T::Hash[String, T.untyped]], catalog_entries: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def merge_api_and_catalog_entries(api_entries, catalog_entries)
    return catalog_entries if api_entries.empty? && catalog_entries.any?
    return api_entries if catalog_entries.empty?

    api_display_names = api_entries.map { |e| e["display_name"].to_s.downcase.strip }.to_set

    # Also track URL-based remote entries by compound key for precise deduplication
    api_url_remote_keys = api_entries.each_with_object(Set.new) do |e, set|
      next unless e["type"] == "remote" && e["id"].to_i == 0 && e["remote_url"].present?
      set << "#{e["remote_url"].to_s.downcase.strip}::#{e["remote_transport_type"].to_s.downcase.strip}"
    end

    merged = api_entries.dup

    catalog_entries.each do |catalog_entry|
      # Check display_name match
      next if api_display_names.include?(catalog_entry["display_name"].to_s.downcase.strip)

      # Check compound URL key match for URL-based remotes
      if catalog_entry["remote_url"].present?
        catalog_key = "#{catalog_entry["remote_url"].to_s.downcase.strip}::#{catalog_entry["remote_transport_type"].to_s.downcase.strip}"
        next if api_url_remote_keys.include?(catalog_key)
      end

      # Catalog entry not in API — append it (unselected by default since it's new)
      merged << catalog_entry.merge("selected" => false)
    end

    merged
  end
end
