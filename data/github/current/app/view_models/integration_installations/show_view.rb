# typed: true
# frozen_string_literal: true

class IntegrationInstallations::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  DEFAULT_INSTALLATION_REASON = "This App was installed automatically by GitHub"

  attr_reader :installation, :installation_request

  delegate :integration, :repositories, :target, to: :installation
  delegate :logo_background_color_style_rule, to: :installation_view

  def installed_at
    installation.created_at
  end

  def installed_automatically?
    installation.installed_automatically?
  end

  def listing
    integration.integration_listing
  end

  def show_features?
    features.any?
  end

  def features
    return [] unless listing && listing.features.any?

    listing.features
  end

  def show_more_info?
    listing.present?
  end

  def automatic_installation_reason
    reason = installation.integration_install_trigger.reason

    return DEFAULT_INSTALLATION_REASON unless reason

    "This App was installed when #{reason}"
  end

  def business_installation?
    target.is_a?(Business)
  end

  def organization_installation?
    target.is_a?(Organization)
  end

  def user_installation?
    !business_installation? && !organization_installation?
  end

  def selected_link
    :integration_installations
  end

  def installed_on_all_repositories?
    return @installed_on_all_repositories if defined?(@installed_on_all_repositories)
    @installed_on_all_repositories = installation.installed_on_all_repositories?
  end

  def installed_on_no_repositories?
    return @installed_on_no_repositories if defined?(@installed_on_no_repositories)
    @installed_on_no_repositories = installation.repositories.none?
  end

  def can_install_on_all_repositories?
    integration.installable_on_all_repositories_by?(target: target, actor: current_user)
  end

  def repository_installation_required?
    if installation.outdated?
      installation.repository_installation_required?
    else
      integration.repository_installation_required?(target)
    end
  end

  def only_select_repositories?
    installation.repositories.any? && !installed_on_all_repositories?
  end

  def installation_request?
    installation_request.present?
  end

  def installation_suggestion?
    !!installation_request&.ephemeral?
  end

  def suggestions_view
    installed_repository_ids = installation.repository_ids unless installed_on_all_repositories?
    IntegrationInstallations::SuggestionsView.new(
      current_user: current_user,
      target: target,
      integration: integration,
      installation: installation,
      installation_request: installation_request,
      exclude: installed_repository_ids,
      edit_installed_repositories: true,
    )
  end

  def permissions_changed_count
    [:permissions_added, :permissions_upgraded].inject(0) do |sum, method|
      sum + permissions_update_request_view.send(method).keys.count
    end
  end

  def installation_view
    @installation_view ||= InstallationView.new(integratable: integration, session: nil, current_user: current_user)
  end

  def permissions_update_request_view
    @permissions_update_request_view ||= IntegrationInstallations::PermissionsUpdateRequestView.new(installation: installation, current_user: current_user)
  end
end
