# typed: true
# frozen_string_literal: true

class IntegrationInstallations::PermissionsUpdateRequestView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :installation

  delegate :integration, :repositories, :target, :version, to: :installation
  delegate :latest_version,                                to: :integration
  delegate :note,                                          to: :latest_version

  delegate :single_file_paths_added, to: :differ
  delegate :single_file_paths_added?, to: :differ
  delegate :single_file_paths_removed, to: :differ
  delegate :single_file_paths_removed?, to: :differ
  delegate :single_file_paths_unchanged, to: :differ
  delegate :single_file_paths_changed?, to: :differ
  delegate :content_references_added?, to: :differ
  delegate :content_references_removed?, to: :differ

  def permissions_added
    differ.permissions_added.keep_if do |_resource, _action|
      relevant_permissions_from(latest_version)
    end
  end

  def permissions_downgraded
    differ.permissions_downgraded.keep_if do |resource, _action|
      relevant_permissions_from(latest_version).key?(resource)
    end
  end

  def permissions_removed
    differ.permissions_removed.keep_if do |resource, _action|
      relevant_permissions_from(version).key?(resource)
    end
  end

  def permissions_unchanged
    differ.permissions_unchanged.keep_if do |resource, _action|
      relevant_permissions_from(latest_version).key?(resource)
    end
  end

  def permissions_upgraded
    differ.permissions_upgraded.keep_if do |resource, _action|
      relevant_permissions_from(latest_version).key?(resource)
    end
  end

  def new_single_files
    single_file_paths_added
  end

  def old_single_files
    single_file_paths_removed
  end

  def unchanged_single_files
    single_file_paths_unchanged
  end

  def added_single_files?
    single_file_paths_added?
  end

  def removed_single_files?
    single_file_paths_removed?
  end

  def new_content_references
    @new_content_references ||= latest_version.default_content_references.keys
  end

  def old_content_references
    @old_content_references ||= version.default_content_references.keys
  end

  def added_content_references?
    content_references_added?
  end

  def removed_content_references?
    content_references_removed?
  end

  def updated_content_references?
    content_references_added? || content_references_removed?
  end

  def repository_installation_required?
    integration.repository_installation_required?(target) && installation.repositories.none?
  end

  # Whether or not the current user is a repository admin and cannot accept
  # these permissions.
  def repo_admin_cannot_accept?
    check = IntegrationInstallation::Permissions.check(
      installation: installation,
      actor:        current_user,
      action:       :update_permissions,
      version:      latest_version,
    )

    !check.permitted?
  end

  def repository_permissions_only?
    integration.repository_permissions_only?
  end

  def installation_manager?
    return false unless installation.target.organization?

    check = IntegrationInstallation::Permissions.check(
      installation: installation,
      actor: current_user,
      action: :view,
    )

    check.permitted? && check.reason != :is_admin
  end

  def update_permissions_path
    if repository_permissions_only? && installation_manager?
      urls.gh_update_app_installation_permissions_path(integration, installation, current_user)
    else
      urls.gh_update_permissions_settings_installation_path(installation)
    end
  end

  def integration_title
    integration.name.sub(/\A(The )?/i, "The ").sub(/( app)?\z/i, " app")
  end

  def was_upgraded?
    integration.versions.count > 1 && !installation.outdated?
  end

  def allow_accept_new_permissions?
    return true unless repository_installation_required?
    suggestions = IntegrationInstallations::SuggestionsView.new(integration: integration, target: target)
    suggestions.install_target_radio_checked?(:all) || suggestions.install_target_radio_checked?(:selected)
  end

  def human_name(resource)
    Permissions::FineGrainedResources::Metadata.title(resource)
  end

  def permission_text(permission)
    Permissions::FineGrainedResources::Metadata.action_description(permission)
  end

  private

  def differ
    @differ ||= IntegrationVersion::Differ.perform(
      old_version: version,
      new_version: latest_version,
    )
  end

  def new_permissions
    @new_permissions ||= latest_version.default_permissions
  end

  def old_permissions
    @old_permissions ||= version.default_permissions
  end

  def relevant_permissions_from(version)
    version.permissions_relevant_to(target)
  end
end
