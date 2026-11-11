# typed: true
# frozen_string_literal: true

class IntegrationInstallations::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  attr_reader :target, :page

  def initialize(attrs = {})
    @update_permissions_memo = {}
    @configure_permissions_memo = {}

    super
  end

  def execute_queries
    GitHub::PrefillAssociations.prefill_associations(installations, [integration: [:marketplace_listing, :latest_version, :avatars]])
    installations.each { |inst| inst.integration&.async_primary_avatar }
    installations.first&.integration&.primary_avatar
  end

  memoize def installations
    installs = if target.is_a?(Repository)
      IntegrationInstallation.with_repository(target)
    else
      target.integration_installations
    end

    target_installations = installs.user_installable.preload(:integration).to_a

    integration_ids = target_installations.filter_map { |install| install.integration_id if install.integration.present? }.uniq
    ids_sorted_by_name = Integration.where(id: integration_ids).order("name asc").pluck(:id)
    sort_position = ids_sorted_by_name.each_with_index.to_h { |id, idx| [id, idx + 1] }

    sorted_installations = target_installations.sort_by { |install| [sort_position.fetch(install.integration_id, 0), install.id] }
    per_page = IntegrationInstallation.per_page
    WillPaginate::Collection.create(page || 1, per_page, sorted_installations.size) do |pager|
      pager.replace(sorted_installations[pager.offset, pager.per_page] || [])
    end
  end

  def update_permissions_path_for(installation)
    if IntegrationInstallation::Permissions.check(installation: installation, actor: current_user, action: :admin).permitted?
      urls.gh_permissions_update_request_settings_installation_path(installation)
    else
      urls.gh_edit_app_installation_permissions_path(installation.integration, installation, current_user)
    end
  end

  def review_request_path_for(installation_request)
    integration = installation_request.integration
    url_params  = { request_id: installation_request }

    if (installation = integration.installations.with_target(target).first)
      urls.settings_org_installation_path(target, installation, url_params)
    else
      url_params[:target_id] = target.id
      urls.gh_app_installation_permissions_path(integration, current_user, **url_params)
    end
  end

  memoize def installation_requests
    return IntegrationInstallationRequest.none unless target.respond_to?(:integration_installation_requests)

    requests = target.integration_installation_requests.preload(:integration)
    requests.select { |r| r.integration.present? }.sort_by { |r| [r.integration.name.downcase, r.id] }
  end

  def can_configure_installation?(installation)
    configure_permissions_for(installation).permitted?
  end

  def configure_installation_as(installation)
    configure_permissions_for(installation).reason
  end

  memoize def can_review_pending_requests?
    return false unless target.is_a?(Organization)
    target.adminable_by?(current_user)
  end

  def automatic_installation_reason(installation)
    installation.integration_install_trigger.reason
  end

  private

  def configure_permissions_for(installation)
    @configure_permissions_memo[installation.id] ||= IntegrationInstallation::Permissions.check(
      installation: installation,
      actor: current_user,
      action: :view,
    )
  end
end
