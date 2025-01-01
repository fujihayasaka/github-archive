# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurationsListComponent < ApplicationComponent
  attr_reader :prebuild_configurations, :current_user, :current_repo, :repo_owner, :prebuild_usage_message

  DISABLE_CONFIG_MSG = "Are you sure you want to disable this prebuild configuration?\nFuture prebuild template creations associated with this configuration will be paused until it is enabled again."

  def initialize(prebuild_configurations: [], current_user:, current_repo:, repo_owner:, prebuild_usage_message: nil)
    @prebuild_configurations = prebuild_configurations
    @prebuild_usage_message = prebuild_usage_message
    @current_user = current_user
    @current_repo = current_repo
    @repo_owner = repo_owner
  end

  memoize def codespaces_enabled_for_org?
    Codespaces::OrgPolicy.enabled_by_organization?(repo_owner)
  end

  memoize def visible_prebuild_configurations
    # This is an extra layer of security to make sure non-production prebuilds aren't shown to non-employees.
    # Employees will still see non-production prebuilds e.g. on gh/gh, but they will be not be editable.
    prebuild_configurations.reject { |config| config.vscs_target&.to_s != "production" && !current_user.employee? }
  end

  def codespaces_disabled?
    return false unless repo_owner.organization?
    return true unless codespaces_enabled_for_org?

    false
  end

  def show_developer_info?
    GitHub.flipper[:codespaces_developer].enabled?(current_user) || GitHub.flipper[:codespaces_developer].enabled?(current_repo) || current_user.employee?
  end

  def setup_docs_url
    "#{GitHub.help_url}/codespaces/managing-codespaces-for-your-organization/enabling-codespaces-for-your-organization"
  end

  def prebuild_docs_url
    "#{GitHub.help_url}/codespaces/customizing-your-codespace/prebuilding-codespaces-for-your-project"
  end

  def regions_number_for_display(configuration)
    pluralize(configuration.targeted_geos.size, "region")

  end

  def regions_list_for_display(configuration)
    configuration.targeted_geos.map { |geo| geo.name }.join(" • ")
  end

  def view_runs_url(configuration)
    workflow_runs_list_path(
      user_id:  current_repo.owner.display_login,
      repository: current_repo,
      workflow_file_name: Codespaces::Prebuilds.workflow_path(configuration.vscs_target),
      query: "branch:#{configuration.branch}",
    )
  end

  def toggle_view_runs_hidden(attrs:, configuration:)
    attrs[:hidden] = true if !configuration.has_ran?
    attrs
  end

  def delete_configuration_msg
    "Are you sure you want to delete this prebuild configuration?\nRunning workflow may fail and templates associated with this configuration will be deleted."
  end

  def actions_disabled?
    # Configurable::ActionsAccess#actions_disabled? takes into consideration the owner entity
    # and returns the most restrictive setting. Using current_repo will work for user, org, and business owners.
    current_repo.actions_disabled?
  end

  def disabled_state?
    codespaces_disabled? || actions_disabled?
  end

  def manual_trigger_disabled?(config)
    disabled_state? || config.disabled? || prebuild_usage_message.present?
  end

  def toggle_disable_button(args:, disabled:)
    if disabled
      args[:disabled] = :true
      args[:tag] = :button # button links can't be disabled
    end

    args
  end

  def show_state_icon(configuration)
    return Primer::Beta::Octicon.new(icon: "play") if configuration.disabled?

    Primer::Beta::Octicon.new(icon: "stop")
  end

  def disable_configuration_msg
    DISABLE_CONFIG_MSG
  end

  def show_devcontainer_path?(configuration)
    return false unless configuration.devcontainer_path.present?
    branch_ref = current_repo.refs.find(configuration.branch)
    pickable_devcontainers = Codespaces::DevContainer.list_dev_containers(current_repo, branch_ref&.target_oid)

    pickable_devcontainers.length > 1
  end

  def show_beta_badge?
    return true if GitHub.flipper[:codespaces_prebuilds_show_beta_badge].enabled?
  end

  def show_permissions_granted?
    GitHub.flipper[:codespaces_prebuilds_show_permissions_granted].enabled?(current_repo)
  end

  # The menu item allows <button> to wrap <a> tags and <a> tags to wrap <button> tags
  # but doesn't allow <button> to wrap <button> tags and <a> tags to wrap <a> tags
  # so we need to flip the menu item wrapper tag to be the opposite of the edit button which needs to be toggled to :button to be disabled properly
  def edit_menu_wrapper_tag
    disabled_state? ? :a : :button
  end

  def editable?(configuration)
    # In order to edit a prebuild configuration (that the user can see to begin with), the prebuild needs to either be
    # for prod OR they need to be a codespaces_developer. Allowing non-developers to edit non-prod prebuilds is a bad
    # experience because we explicitly hide all of the targeting details on the edit page if they aren't flagged in.
    !disabled_state? && (configuration.vscs_target == :production || current_user.feature_enabled?(:codespaces_developer))
  end

  def delete_prebuild_config_id(configuration)
    "delete-prebuild-configuration-#{configuration.id}-dialog"
  end
end
