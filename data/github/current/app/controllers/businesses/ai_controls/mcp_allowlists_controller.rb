# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_allowlist_client"

class Businesses::AiControls::McpAllowlistsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared
  include Businesses::AiControls::McpAllowlistShared

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AiControls::McpAllowlistsController#create",
    "Businesses::AiControls::McpAllowlistsController#update",
    "Businesses::AiControls::McpAllowlistsController#destroy",
    "Businesses::AiControls::McpAllowlistsController#add_server",
    "Businesses::AiControls::McpAllowlistsController#remove_server",
  ].freeze

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Authnd

  layout "layouts/react_business"

  allow_verified_fetch only: [:index]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :ai_controls_read_required
  before_action :ensure_allowlist_feature_flag_enabled
  before_action :ai_controls_write_required, only: [:create, :update, :destroy, :add_server, :remove_server]

  rescue_from McpRegistry::EnterpriseAllowlistClient::ApiError, with: :handle_api_error

  sig { void }
  def index
    allowlists, allowlists_load_failed = fetch_allowlists
    assignments = fetch_assignments
    organizations = this_business.organizations.order(:login)

    name_validation = allowlist_name_validation_enabled?

    render "businesses/ai_controls/mcp/allowlists", locals: {
      business: this_business,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
      title: "MCP Allowlists",
      allowlists: allowlists,
      allowlists_load_failed: allowlists_load_failed,
      assignments: assignments,
      organizations: organizations,
      require_name_validation: name_validation,
    }
  end

  sig { void }
  def create
    name = params.dig(:allowlist, :name).to_s.strip
    description = params.dig(:allowlist, :description).to_s.strip.presence

    if name.blank?
      flash[:error] = "Allowlist name is required."
      redirect_to allowlists_redirect_path
      return
    end

    enterprise_id = this_business.id.to_s
    result = McpRegistry::EnterpriseAllowlistClient.create_allowlist(
      enterprise_id: enterprise_id,
      name: name,
      description: description,
      actor_id: current_user.id,
      token: mcp_registry_token,
    )

    allowlist_id = result["public_id"] || result["id"]
    failed = allowlist_id.present? ? sync_servers(enterprise_id: enterprise_id, allowlist_id: allowlist_id.to_s) : []
    failed += allowlist_id.present? ? sync_server_entries(enterprise_id: enterprise_id, allowlist_id: allowlist_id.to_s) : []
    failed += allowlist_id.present? ? sync_org_assignments(enterprise_id: enterprise_id, allowlist_id: allowlist_id.to_s) : []

    if failed.any?
      flash[:warning] = "Allowlist created, but some operations failed: #{failed.join(', ')}"
    else
      flash[:success] = "Your new MCP allowlist has been successfully created."
    end
    redirect_to allowlists_redirect_path
  rescue StandardError => e
    raise if e.is_a?(McpRegistry::EnterpriseAllowlistClient::ApiError)
    Rails.logger.error("MCP_Registry_Enterprise_Error: create failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to allowlists_redirect_path
  end

  sig { void }
  def update
    allowlist_id = params[:id].to_s
    name = params.dig(:allowlist, :name).to_s.strip.presence
    description = params.dig(:allowlist, :description).to_s.strip

    enterprise_id = this_business.id.to_s
    McpRegistry::EnterpriseAllowlistClient.update_allowlist(
      enterprise_id: enterprise_id,
      allowlist_id: allowlist_id,
      name: name,
      description: description,
      actor_id: current_user.id,
      token: mcp_registry_token,
    )

    failed = sync_servers(enterprise_id: enterprise_id, allowlist_id: allowlist_id) +
             remove_servers(enterprise_id: enterprise_id, allowlist_id: allowlist_id) +
             sync_server_entries(enterprise_id: enterprise_id, allowlist_id: allowlist_id)

    current_assignments = fetch_assignments.select { |a| (a.dig("allowlist", "public_id") || a["allowlist_id"] || a["allowlist_public_id"]) == allowlist_id }
    current_org_ids = current_assignments.map { |a| a["namespace_id"].to_s }

    failed += sync_org_assignments(enterprise_id: enterprise_id, allowlist_id: allowlist_id, current_org_ids: current_org_ids)

    if failed.any?
      flash[:warning] = "Allowlist updated, but some operations failed: #{failed.join(', ')}"
    else
      flash[:success] = "Allowlist updated successfully."
    end
    redirect_to allowlists_redirect_path
  rescue StandardError => e
    raise if e.is_a?(McpRegistry::EnterpriseAllowlistClient::ApiError)
    Rails.logger.error("MCP_Registry_Enterprise_Error: update failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to allowlists_redirect_path
  end

  sig { void }
  def destroy
    allowlist_id = params[:id].to_s

    McpRegistry::EnterpriseAllowlistClient.delete_allowlist(
      enterprise_id: this_business.id.to_s,
      allowlist_id: allowlist_id,
      token: mcp_registry_token,
    )

    flash[:success] = "Allowlist deleted successfully."
    redirect_to allowlists_redirect_path
  rescue StandardError => e
    raise if e.is_a?(McpRegistry::EnterpriseAllowlistClient::ApiError)
    Rails.logger.error("MCP_Registry_Enterprise_Error: delete failed: #{e.class}: #{e.message}")
    flash[:error] = "Something went wrong. Please try again."
    redirect_to allowlists_redirect_path
  end

  # List available servers from the MCP registry for the "select server" dropdown.
  #
  # GET /enterprises/:enterprise_id/ai_controls/mcp/allowlists/servers
  sig { void }
  def servers # rubocop:disable GitHub/UseRestfulActions
    search = params[:search].presence || params[:q].presence
    page = params[:page].present? ? params[:page].to_i : 1
    per_page = params[:per_page].present? ? params[:per_page].to_i : 100

    result = McpRegistry::EnterpriseAllowlistClient.list_servers(
      search: search,
      page: page,
      per_page: per_page,
      token: mcp_registry_token,
    )

    servers = result["servers"] || []

    # Enrich each server with a public_id from the registry metadata
    # so the SelectPanel template can use it as the value attribute.
    servers.each do |server_wrapper|
      server_obj = server_wrapper.is_a?(Hash) && server_wrapper.key?("server") ? server_wrapper["server"] : server_wrapper
      next unless server_obj.is_a?(Hash)

      github_meta = server_obj.dig("_meta", "io.modelcontextprotocol.registry/publisher-provided", "github")
      public_id = github_meta&.dig("publicId")
      server_obj["public_id"] = public_id if public_id.present?
    end

    respond_to do |format|
      format.json { render json: result }
      format.any(:html, :html_fragment) do
        render partial: "businesses/ai_controls/mcp/server_select_panel_list",
               locals: { servers: servers },
               layout: false,
               formats: [:html, :html_fragment]
      end
    end
  rescue StandardError => e
    raise if e.is_a?(McpRegistry::EnterpriseAllowlistClient::ApiError)
    Rails.logger.error("MCP_Registry_Enterprise_Error: Error fetching servers: #{e.class}: #{e.message}")
    respond_to do |format|
      format.json { render plain: "Unable to load servers. Please try again.", status: :internal_server_error }
      format.any(:html, :html_fragment) { render plain: "Unable to load servers", status: :internal_server_error }
    end
  end

  sig { void }
  def add_server # rubocop:disable GitHub/UseRestfulActions
    render json: McpRegistry::EnterpriseAllowlistClient.add_server_to_allowlist(
      enterprise_id: this_business.id.to_s,
      allowlist_id: params[:allowlist_id].to_s,
      server_id: params[:server_id].to_s,
      token: mcp_registry_token,
    )
  end

  sig { void }
  def remove_server # rubocop:disable GitHub/UseRestfulActions
    render json: McpRegistry::EnterpriseAllowlistClient.remove_server_from_allowlist(
      enterprise_id: this_business.id.to_s,
      allowlist_id: params[:allowlist_id].to_s,
      server_id: params[:server_id].to_s,
      token: mcp_registry_token,
    )
  end

  private

  sig { override.returns(String) }
  def ai_controls_section_title
    "MCP Allowlists"
  end

  sig { override.returns(Symbol) }
  def ai_controls_selected_link
    :businesses_ai_controls_mcp
  end

  sig { returns(String) }
  def allowlists_redirect_path
    mcp_allowlists_enterprise_ai_controls_enterprise_path(this_business)
  end

  # Iterates server params under the given key, calling the block for each server_id.
  # Returns an array of display names for servers that failed.
  sig { params(param_key: Symbol, enterprise_id: String, allowlist_id: String, block: T.proc.params(arg0: String).void).returns(T::Array[String]) }
  def batch_server_operation(param_key, enterprise_id:, allowlist_id:, &block)
    server_params = params.dig(:allowlist, param_key)
    return [] unless server_params.present?

    failed = T.let([], T::Array[String])
    server_params.each_value do |server|
      server_id = server[:public_id].to_s.strip
      next if server_id.blank?

      yield(server_id)
    rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
      Rails.logger.warn("[MCP AllowlistsController] Server operation failed for #{server_id}: #{e.status} #{e.message}")
      failed << (server[:name].presence || server_id)
    end
    failed
  end

  # Adds each server from the form's allowlist[servers] params to the allowlist via the API.
  sig { params(enterprise_id: String, allowlist_id: String).returns(T::Array[String]) }
  def sync_servers(enterprise_id:, allowlist_id:)
    token = mcp_registry_token
    batch_server_operation(:servers, enterprise_id: enterprise_id, allowlist_id: allowlist_id) do |server_id|
      McpRegistry::EnterpriseAllowlistClient.add_server_to_allowlist(
        enterprise_id: enterprise_id, allowlist_id: allowlist_id, server_id: server_id, token: token,
      )
    end
  end

  # Removes each server from the form's allowlist[removed_servers] params from the allowlist via the API.
  sig { params(enterprise_id: String, allowlist_id: String).returns(T::Array[String]) }
  def remove_servers(enterprise_id:, allowlist_id:)
    token = mcp_registry_token
    batch_server_operation(:removed_servers, enterprise_id: enterprise_id, allowlist_id: allowlist_id) do |server_id|
      McpRegistry::EnterpriseAllowlistClient.remove_server_from_allowlist(
        enterprise_id: enterprise_id, allowlist_id: allowlist_id, server_id: server_id, token: token,
      )
    end
  end

  # Updates selected entries (remotes/packages) for each server that has entry selections.
  # Reads from allowlist[servers][N][entries][] params containing JSON-encoded entry objects.
  # Returns an array of server names that failed entry sync.
  sig { params(enterprise_id: String, allowlist_id: String).returns(T::Array[String]) }
  def sync_server_entries(enterprise_id:, allowlist_id:)
    server_params = params.dig(:allowlist, :servers)
    return [] unless server_params.present?

    token = mcp_registry_token
    failed = T.let([], T::Array[String])
    valid_types = %w[remote package]

    # Fallback: read top-level server_entries checkboxes in case JS didn't
    # transfer them into per-server hidden inputs.
    top_level_entries = parse_server_entries_param(valid_types)

    server_params.each_value do |server|
      server_id = server[:public_id].to_s.strip
      next if server_id.blank?

      entry_params = server[:entries]
      entries_loaded = server[:entries_loaded] == "1"

      # Skip servers whose entries UI was never shown (no entries loaded marker)
      next unless entry_params.present? || entries_loaded

      # Parse selected entries from form params
      form_entries = parse_entry_params(entry_params, valid_types)

      # Fallback: if per-server entries are empty but top-level server_entries
      # exist (checkboxes submitted but not transferred to hidden inputs by JS),
      # use those for this server.
      if form_entries.empty? && top_level_entries.any?
        form_entries = top_level_entries
        # Only consume top-level entries once (for the first server needing them)
        top_level_entries = []
      end

      # Resolve form entries against real registry IDs. Catalog-generated entries
      # have fake sequential IDs that the registry rejects. Fetch the real
      # available entries from the API and match by type so we submit real IDs.
      entries = resolve_entry_ids(enterprise_id: enterprise_id, allowlist_id: allowlist_id, server_id: server_id, form_entries: form_entries, token: token)

      Rails.logger.info("[MCP AllowlistsController] Syncing #{entries.length} entries for server=#{server_id} in allowlist=#{allowlist_id}")
      McpRegistry::EnterpriseAllowlistClient.update_server_entries(
        enterprise_id: enterprise_id,
        allowlist_id: allowlist_id,
        server_id: server_id,
        entries: entries,
        token: token,
      )
    rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
      Rails.logger.warn("[MCP AllowlistsController] Entry sync failed for server #{server_id}: #{e.status} #{e.message}")
      failed << (server[:name].presence || server_id)
    end

    failed
  end

  # Parses JSON-encoded entry strings from form params into structured hashes
  # with the appropriate type-specific ID field.
  sig { params(entry_params: T.untyped, valid_types: T::Array[String]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def parse_entry_params(entry_params, valid_types)
    Array(entry_params).filter_map do |entry_json|
      parsed = JSON.parse(entry_json)
      next unless parsed.is_a?(Hash)

      entry_type = parsed["type"].to_s
      transport_id = parsed["transport_id"].to_i
      package_id = entry_type == "package" ? (parsed["package_id"] || parsed["transport_id"]).to_i : 0
      display_name = parsed["display_name"].to_s
      remote_url = parsed["remote_url"].to_s.presence
      remote_transport_type = parsed["remote_transport_type"].to_s.presence

      # Accept entries with an explicit identifier OR entries with just type+display_name
      # (display_name-only entries will be resolved against the API in resolve_entry_ids).
      has_identifier = transport_id > 0 || package_id > 0 || remote_url.present?
      has_display_name = display_name.present?
      next unless valid_types.include?(entry_type) && (has_identifier || has_display_name)

      entry = { "type" => entry_type, "display_name" => display_name }
      if entry_type == "remote" && remote_url.present?
        entry["remote_url"] = remote_url
        entry["remote_transport_type"] = remote_transport_type if remote_transport_type
      elsif entry_type == "remote" && transport_id > 0
        entry["transport_id"] = transport_id
      elsif entry_type == "package" && package_id > 0
        entry["package_id"] = package_id
      end
      entry
    rescue JSON::ParserError
      nil
    end
  end

  # Reads the top-level server_entries checkbox param as a fallback when JS
  # hasn't transferred values into per-server hidden inputs.
  sig { params(valid_types: T::Array[String]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def parse_server_entries_param(valid_types)
    return [] unless params[:server_entries].present?
    parse_entry_params(Array(params[:server_entries]), valid_types)
  end

  # Resolves form entries against real registry IDs by matching on display_name
  # or URL compound key. Falls back to form data on API error.
  sig { params(enterprise_id: String, allowlist_id: String, server_id: String, form_entries: T::Array[T::Hash[String, T.untyped]], token: T.nilable(String)).returns(T::Array[T::Hash[String, T.untyped]]) }
  def resolve_entry_ids(enterprise_id:, allowlist_id:, server_id:, form_entries:, token:)
    return form_entries if form_entries.empty?

    api_result = McpRegistry::EnterpriseAllowlistClient.list_server_entries(
      enterprise_id: enterprise_id,
      allowlist_id: allowlist_id,
      server_id: server_id,
      token: token,
    )
    api_entries = Array(api_result.dig("entries"))

    if api_entries.empty?
      return form_entries.filter_map { |e| build_api_entry(e) }
    end

    # Build lookup of real entries by normalized display_name for stable matching
    api_by_display_name = api_entries.each_with_object({}) do |entry, hash|
      key = entry["display_name"].to_s.downcase.strip
      hash[key] = entry unless key.empty?
    end

    # Build lookup of URL-based remote entries by compound key for precise matching
    api_url_remotes_by_key = api_entries.each_with_object({}) do |entry, hash|
      next unless entry["type"] == "remote" && entry["id"].to_i == 0 && entry["remote_url"].present?
      key = url_remote_key(entry["remote_url"], entry["remote_transport_type"])
      hash[key] = entry
    end

    resolved = T.let([], T::Array[T::Hash[String, T.untyped]])
    form_entries.each do |form_entry|
      # For URL-based remotes, try compound key match first
      if form_entry["remote_url"].present?
        key = url_remote_key(form_entry["remote_url"], form_entry["remote_transport_type"])
        matched = api_url_remotes_by_key[key]
        if matched
          api_entry = build_api_entry(matched)
          resolved << api_entry if api_entry
          next
        end
      end

      form_display_name = form_entry["display_name"].to_s.downcase.strip
      matched_api_entry = api_by_display_name[form_display_name]

      # Fallback: JS may send display_name as "transport: url" while the API uses
      # just "url". Extract the URL part and try matching.
      if matched_api_entry.nil? && form_entry["type"] == "remote" && form_display_name.include?(":")
        url_part = form_display_name.split(": ", 2).last.to_s.strip
        if url_part.present?
          transport_part = form_display_name.split(": ", 2).first.to_s.strip
          matched_api_entry = api_url_remotes_by_key[url_remote_key(url_part, transport_part)] ||
                              api_by_display_name[url_part]
        end
      end

      if matched_api_entry
        api_entry = build_api_entry(matched_api_entry)
        resolved << api_entry if api_entry
      else
        Rails.logger.warn("MCP allowlist: no API match for entry display_name=#{form_entry["display_name"].inspect} type=#{form_entry["type"]}")
        api_entry = build_api_entry(form_entry)
        resolved << api_entry if api_entry
      end
    end

    resolved
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    Rails.logger.warn("MCP allowlist: API error fetching entries (#{e.status}), falling back to form data")
    form_entries.filter_map { |e| build_api_entry(e) }
  end

  # Builds an API-compatible entry hash with the correct type-specific ID field.
  # Returns nil when the entry cannot be properly identified.
  sig { params(entry: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[String, T.untyped])) }
  def build_api_entry(entry)
    type = entry["type"].to_s
    remote_url = entry["remote_url"]

    # URL-based remote: no database row, identified by URL
    if type == "remote" && remote_url.present?
      result = { "type" => type, "remote_url" => remote_url }
      result["remote_transport_type"] = entry["remote_transport_type"] if entry["remote_transport_type"].present?
      return result
    end

    # Transport-backed remote (id > 0) or package (id > 0)
    if type == "package"
      id = (entry["package_id"] || entry["id"]).to_i
      return nil unless id > 0
      { "type" => type, "package_id" => id }
    else
      id = (entry["transport_id"] || entry["id"]).to_i
      return nil unless id > 0
      { "type" => type, "transport_id" => id }
    end
  end

  # Builds a compound lookup key for URL-based remote entries.
  sig { params(remote_url: T.nilable(String), remote_transport_type: T.nilable(String)).returns(String) }
  def url_remote_key(remote_url, remote_transport_type)
    "#{remote_url&.downcase&.strip}::#{remote_transport_type&.downcase&.strip}"
  end

  # Assigns the allowlist to the organizations selected in the form (allowlist[organization_ids][]).
  # For each selected org, calls PUT /{enterpriseID}/namespaces/organization/{orgID}/assignment.
  # Also unassigns orgs that were previously assigned but are no longer selected.
  # Returns an array of org IDs that failed to assign or unassign.
  sig { params(enterprise_id: String, allowlist_id: String, current_org_ids: T::Array[String]).returns(T::Array[String]) }
  def sync_org_assignments(enterprise_id:, allowlist_id:, current_org_ids: [])
    org_ids = params.dig(:allowlist, :organization_ids)
    selected_org_ids = Array(org_ids).map { |id| id.to_s.strip }.reject(&:blank?)

    token = mcp_registry_token
    failed = T.let([], T::Array[String])

    selected_org_ids.each do |org_id|
      Rails.logger.info("[MCP AllowlistsController] Assigning allowlist=#{allowlist_id} to namespace_type=org namespace_id=#{org_id}")
      McpRegistry::EnterpriseAllowlistClient.assign_allowlist(
        enterprise_id: enterprise_id,
        namespace_type: "org",
        namespace_id: org_id,
        allowlist_id: allowlist_id,
        token: token,
      )
    rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
      Rails.logger.warn("[MCP AllowlistsController] Org assignment failed for org_id=#{org_id}: #{e.status} #{e.message}")
      failed << org_id
    end

    # Unassign orgs that were previously assigned but are no longer selected
    orgs_to_unassign = current_org_ids - selected_org_ids
    orgs_to_unassign.each do |org_id|
      next if org_id.blank?

      Rails.logger.info("[MCP AllowlistsController] Unassigning allowlist=#{allowlist_id} from namespace_type=org namespace_id=#{org_id}")
      McpRegistry::EnterpriseAllowlistClient.unassign_allowlist(
        enterprise_id: enterprise_id,
        namespace_type: "org",
        namespace_id: org_id,
        token: token,
      )
    rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
      Rails.logger.warn("[MCP AllowlistsController] Org unassignment failed for org_id=#{org_id}: #{e.status} #{e.message}")
      failed << org_id
    end

    failed
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { returns([T::Array[T::Hash[String, T.untyped]], T::Boolean]) }
  def fetch_allowlists
    enterprise_id = this_business.id.to_s
    token = mcp_registry_token
    result = McpRegistry::EnterpriseAllowlistClient.list_allowlists(enterprise_id: enterprise_id, token: token)
    allowlists = result["allowlists"] || result.fetch("items", [])
    [enrich_allowlists(allowlists), false]
  rescue StandardError => e
    Rails.logger.error("MCP_Registry_Enterprise_Error: Error fetching allowlists: #{e.class}: #{e.message}")
    [[], true]
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def fetch_assignments
    enterprise_id = this_business.id.to_s
    token = mcp_registry_token
    result = McpRegistry::EnterpriseAllowlistClient.list_assignments(enterprise_id: enterprise_id, token: token)
    assignments = result["assignments"] || result.fetch("items", [])
    assignments
  rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
    Rails.logger.error("MCP_Registry_Enterprise_Error: ApiError fetching assignments: #{e.class}: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("MCP_Registry_Enterprise_Error: Error fetching assignments: #{e.class}: #{e.message}")
    []
  end

  sig { params(error: McpRegistry::EnterpriseAllowlistClient::ApiError).void }
  def handle_api_error(error)
    message = case error.status
    when 409 then "An allowlist with that name already exists."
    when 422 then "Validation failed. Please check your input."
    when 403 then "You don't have permission to perform this action."
    when 404 then "The requested resource could not be found."
    else "Something went wrong. Please try again."
    end

    respond_to do |format|
      format.json { render plain: message, status: error.status }
      format.html_fragment { render plain: message, status: error.status }
      format.html do
        flash[:error] = message
        redirect_to allowlists_redirect_path
      end
    end
  end

  # Enriches allowlist entries by resolving user IDs in created_by/updated_by
  # to hashes with login and avatar_url, and fetching servers for each allowlist.
  sig { params(allowlists: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def enrich_allowlists(allowlists)
    # Resolve user IDs to user objects
    user_ids = allowlists.flat_map { |a| [a["created_by"], a["updated_by"]] }.compact.grep(Integer).uniq

    if user_ids.any?
      users_by_id = User.where(id: user_ids).index_by(&:id)

      allowlists.each do |allowlist|
        %w[created_by updated_by].each do |field|
          val = allowlist[field]
          next unless val.is_a?(Integer)

          user = users_by_id[val]
          allowlist[field] = if user
            { "login" => user.display_login, "avatar_url" => user.primary_avatar_url }
          else
            { "login" => "user-#{val}", "avatar_url" => nil }
          end
        end
      end
    end

    # Fetch servers for each allowlist if not already present
    enterprise_id = this_business.id.to_s
    token = mcp_registry_token

    # Collect all server references that need enrichment
    allowlists_needing_servers = allowlists.reject { |a| a["servers"].present? }

    allowlists_needing_servers.each do |allowlist|
      allowlist_id = allowlist["public_id"] || allowlist["id"]
      next if allowlist_id.blank?

      result = McpRegistry::EnterpriseAllowlistClient.list_allowlist_servers(
        enterprise_id: enterprise_id,
        allowlist_id: allowlist_id.to_s,
        token: token,
      )
      allowlist["_raw_servers"] = result["servers"] || []
    rescue McpRegistry::EnterpriseAllowlistClient::ApiError => e
      Rails.logger.warn("[MCP AllowlistsController] Failed to fetch servers for allowlist #{allowlist_id}: #{e.status} #{e.message}")
      allowlist["_raw_servers"] = []
    rescue StandardError => e
      Rails.logger.error("MCP_Registry_Enterprise_Error: Error fetching servers for allowlist #{allowlist_id}: #{e.class}: #{e.message}")
      allowlist["_raw_servers"] = []
    end

    # Build a lookup of full server details from the public registry API.
    # The allowlist servers endpoint returns only references (server_public_id),
    # so we need to fetch the full catalog to resolve names, descriptions, and URLs.
    all_server_public_ids = allowlists_needing_servers.flat_map { |a| (a["_raw_servers"] || []).map { |s| s["server_public_id"] } }.compact.uniq
    server_details_by_id = {}

    if all_server_public_ids.any?
      server_details_by_id = fetch_server_details_by_public_id(all_server_public_ids, token: token)
    end

    # Enrich each allowlist's server references with full details
    allowlists_needing_servers.each do |allowlist|
      raw_servers = allowlist.delete("_raw_servers") || []
      allowlist["servers"] = raw_servers.map do |raw|
        normalize_server_entry(raw, server_details_by_id)
      end
    end

    allowlists
  end

  # Fetches full server details from the public registry API and builds a lookup by publicId.
  sig { params(server_public_ids: T::Array[String], token: T.nilable(String)).returns(T::Hash[String, T::Hash[String, T.untyped]]) }
  def fetch_server_details_by_public_id(server_public_ids, token: nil)
    lookup = T.let({}, T::Hash[String, T::Hash[String, T.untyped]])

    page = 1
    # Build a normalized (dashless) → original ID map so we can match
    # legacy hex IDs against UUID-formatted publicIds from the catalog.
    remaining = server_public_ids.each_with_object({}) { |id, h| h[id.delete("-")] = id }

    loop do
      break if remaining.empty?

      result = McpRegistry::EnterpriseAllowlistClient.list_servers(page: page, per_page: 100, token: token)
      servers = result["servers"] || []
      break if servers.empty?

      servers.each do |entry|
        server_obj = entry.is_a?(Hash) && entry.key?("server") ? entry["server"] : entry
        next unless server_obj.is_a?(Hash)

        github_meta = server_obj.dig("_meta", "io.modelcontextprotocol.registry/publisher-provided", "github")
        public_id = github_meta&.dig("publicId")
        next unless public_id.present?

        normalized = public_id.delete("-")
        original_id = remaining[normalized]
        next unless original_id

        first_remote_url = server_obj.dig("remotes", 0, "url")
        lookup[original_id] = {
          "name" => server_obj["name"],
          "description" => server_obj["description"],
          "url" => first_remote_url,
          "public_id" => public_id,
        }
        remaining.delete(normalized)
      end

      total_pages = result.dig("metadata", "total_pages") || 1
      break if page >= total_pages

      page += 1
    end

    lookup
  rescue StandardError => e
    Rails.logger.error("MCP_Registry_Enterprise_Error: Error fetching server catalog: #{e.class}: #{e.message}")
    lookup || {}
  end

  # Normalizes a raw server reference from the allowlist servers API into the
  # shape expected by the view: {name, description, url, public_id}.
  sig { params(raw: T::Hash[String, T.untyped], details_lookup: T::Hash[String, T::Hash[String, T.untyped]]).returns(T::Hash[String, T.untyped]) }
  def normalize_server_entry(raw, details_lookup)
    # If the raw entry already has a "server" sub-object (full MCP schema), unwrap it
    if raw.key?("server") && raw["server"].is_a?(Hash)
      server_obj = raw["server"]
      first_remote_url = server_obj.dig("remotes", 0, "url")
      github_meta = server_obj.dig("_meta", "io.modelcontextprotocol.registry/publisher-provided", "github")
      resolved_id = github_meta&.dig("publicId") || raw["public_id"] || server_obj["name"]
      return {
        "name" => server_obj["name"],
        "description" => server_obj["description"],
        "url" => first_remote_url || server_obj["url"],
        "public_id" => resolved_id,
      }
    end

    # If the raw entry already has name (flat format), use it directly
    if raw["name"].present?
      return {
        "name" => raw["name"],
        "description" => raw["description"],
        "url" => raw["url"],
        "public_id" => raw["public_id"] || raw["name"],
      }
    end

    # The allowlist servers API returns only a reference (server_public_id).
    # Look up the full details from the public catalog.
    server_public_id = raw["server_public_id"]
    if server_public_id.present? && details_lookup.key?(server_public_id)
      return T.must(details_lookup[server_public_id])
    end

    # Fallback: use server_public_id as-is
    {
      "name" => server_public_id || raw["id"],
      "description" => nil,
      "url" => nil,
      "public_id" => server_public_id || raw["public_id"] || raw["id"],
    }
  end
end
