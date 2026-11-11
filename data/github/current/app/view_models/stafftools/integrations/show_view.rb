# typed: true
# frozen_string_literal: true

class Stafftools::Integrations::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :integration
  attr_reader :hook_deliveries_query
  attr_reader :query

  delegate :name, :hook, :created_at, :owner, :id, to: :integration

  def page_title
    "Owned Integrations - #{ name }"
  end

  def selected_link
    :integrations
  end

  # Maximum time we'll spend computing the total installations count before
  # giving up. The underlying `SELECT COUNT(*) FROM integration_installations`
  # can be very slow for popular apps (e.g. github-actions) and has caused 500s
  # on this stafftools page when killed by the query reaper.
  INSTALLATIONS_COUNT_TIMEOUT_MS = 2_000

  # Returns the total number of installations for this integration, or nil if
  # the count query times out. Callers should treat nil as "unavailable" and
  # render a fallback rather than failing the whole page.
  def installations_count
    return @installations_count if defined?(@installations_count)

    @installations_count = begin
      integration.installations
        .limit_execution_time(limit_ms: INSTALLATIONS_COUNT_TIMEOUT_MS)
        .count
    rescue ActiveRecord::QueryCanceled, ActiveRecord::StatementTimeout
      nil
    end
  end

  def has_automatic_installs?
    integration_install_triggers.any?
  end

  def has_marketplace_listing?
    listing.present?
  end

  def listing
    @listing ||= Marketplace::Listing.for_integratables(nil, id).first
  end

  def integration_install_triggers
    @integration_install_triggers ||= IntegrationInstallTrigger.install_types.keys.map do |install_type|
      IntegrationInstallTrigger.latest(integration: integration, install_type: install_type)
    end.compact
  end

  def integration_install_trigger_string
    integration_install_triggers.map(&:install_type).to_sentence
  end

  def yaml_manifest
    YAML.dump(manifest_hash)
  end

  def json_manifest
    GitHub::JSON.encode(manifest_hash)
  end

  def manifest_hash
    {
      "name"                => "Manifest - #{name}"[0..30],
      "url"                 => "http://example.com",
      "hook_attributes"     => { "url" => "http://example.com/hooks" },
      "redirect_url"        => "http://example.com/manifest/creation/callback",
      "description"         => "Manifest App created from [#{name}](#{urls.stafftools_user_app_path(integration.owner, integration)})",
      "public"              => false,
      "events"              => integration.default_events,
      "permissions"         => integration.default_permissions,
    }
  end

  def this_app_managers
    manager_ids = Apps::ManagementHelper.user_ids_with_app_owner_role(on: integration)
    User.where(id: manager_ids)
  end

  def organization_app_managers
    manager_ids = Apps::ManagementHelper.user_ids_with_app_manager_role(on: integration.owner)
    User.where(id: manager_ids)
  end

  def ip_allowlist_entries
    return @ip_allowlist_entries if defined?(@ip_allowlist_entries)
    @ip_allowlist_entries = IpAllowlistEntry.usable_for(integration)
      .for_query(query)
      .order(allow_list_value: :asc)
  end

  def hook_active_status
    hook.active? ? "enabled" : "disabled"
  end

  def bot
    @bot ||= integration.bot
  end

  def bot_suspended?
    bot&.suspended? || false
  end

  def bot_suspended_at
    bot&.suspended_at
  end

  def agent_setup_configured?
    agent_source.present? && agent_source.repository.present? && agent_source.commit_oid.present?
  end

  def agent_setup_repository_name
    return "N/A" unless agent_setup_configured?

    agent_source.repository.name_with_display_owner
  end

  def agent_setup_commit_oid
    return "N/A" unless agent_setup_configured?

    agent_source.commit_oid
  end

  def agent_setup_commit_url
    return unless agent_setup_configured?

    urls.repository_tree_path(agent_source.repository, agent_source.commit_oid, :tree, nil)
  end

  def owner_soft_deleted_org?
    owner = @integration.owner
    owner.is_a?(::Organization) && T.let(owner, ::Organization).soft_deleted?
  end

  def show_unable_to_transfer_to_biz_message?
    integration.owner.is_a?(User) &&
    integration.public_visibility? &&
    !is_enterprise_managed?
  end

  def uninstall_warning_text
    prefix = "When the transfer is completed, this app will be automatically uninstalled from"

    owner = integration.owner

    case owner
    when Organization
      "#{prefix} the #{owner.display_login} organization."
    else
      "#{prefix} your account."
    end
  end

  def enterprise_owned_with_installations?
    integration.owner.business? && integration.installations.any?
  end

  def disable_uninstall_all_button?
    pending_bulk_uninstall? || integration.installations.none?
  end

  def pending_bulk_uninstall?
    Integration.locked_for_bulk_uninstalls?(integration)
  end

  def pending_bulk_uninstall_text
    count = installations_count
    return "Uninstalling installations..." if count.nil?

    "Uninstalling #{count} #{"installation".pluralize(count)}..."
  end

  private

  def agent_source
    @agent_source ||= integration.agent_source
  end

  def is_enterprise_managed?
    owner = integration.owner
    case owner
    when Organization
      owner.enterprise_managed_user_enabled?
    when User
      owner.is_enterprise_managed?
    else
      false
    end
  end
end
