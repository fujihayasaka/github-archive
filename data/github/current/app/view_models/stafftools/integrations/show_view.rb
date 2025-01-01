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

  def installations_count
    integration.installations.count
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
    "Uninstalling #{installations_count} #{"installation".pluralize(installations_count)}..."
  end

  private

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
