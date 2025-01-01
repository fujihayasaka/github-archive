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
    manager_ids = Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: integration.id)
    User.where(id: manager_ids)
  end

  def organization_app_managers
    manager_ids = Permissions::Enumerator.actor_ids_with_permission(action: :manage_all_apps, subject_id: owner.id)
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
end
