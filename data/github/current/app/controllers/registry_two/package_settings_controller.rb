# typed: true
# frozen_string_literal: true

class RegistryTwo::PackageSettingsController < RegistryTwo::Controller
  include RegistryTwo::MembersHelper

  before_action :ensure_package
  before_action :ensure_package_admin
  before_action :ensure_v2_package
  before_action :ensure_v2_ui_enabled
  before_action :load_actor_from_params, only: [:add_collaborator, :update_collaborator, :remove_collaborator]
  before_action :load_repo_from_params, only: [:add_actions_access, :update_actions_access, :remove_actions_access, :add_codespaces_access, :remove_codespaces_access]
  before_action :load_codespace_integration, only: [:add_codespaces_access, :remove_codespaces_access, :bulk_add_codespaces_access]
  before_action :load_actions_integration, only: [:add_actions_access, :update_actions_access, :remove_actions_access, :bulk_update_actions_access, :bulk_add_actions_access]
  before_action :spammy_behaviour_check

  attr_reader :actor, :integration

  javascript_bundle :packages
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    only: [:collaborator_suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    repository_action = RepositoryAction.find_by(repository: package.repository)

    render "registry_two/package_settings/show", locals: {
      package:,
      members_to_roles:,
      actions_packages_permissions:,
      codespaces_packages_permissions:,
      show_reclaimed_storage: show_reclaimed_storage?,
      reclaimed_storage:,
      viewer_can_read_repo: current_user_can_read_repo?,
      repository_action:,
      user_type: params[:user_type] || get_owner_type
    }
  end

  def add_collaborator # rubocop:todo GitHub/UseRestfulActions
    # If owner is an organization, verify actor is org member.
    unless actor_can_be_granted_permissions?
      flash[:error] = "Can't grant permissions to users who cannot access this organization."
      return redirect_to :back
    end

    # Give all new collaborators the lowest permission level: read.
    Permissions::Granters::RoleGranter.new(
      actor: actor, target: package, role: Role.package_reader_role
    ).grant!

    redirect_to :back
  end

  def add_actions_access # rubocop:todo GitHub/UseRestfulActions
    unless actions_can_be_granted_permissions?
      flash[:error] = "Can't grant permissions to inaccessible repository."
      return redirect_to :back
    end

    # Add read role as initial grant
    integration_allowed_packages = IntegrationAllowedPackage.new(repository_id: @actor.id, access_type: "contents", package_id: package.id, integration_id: integration.id)

    IntegrationAllowedPackage.transaction do
      # Clean up any old roles if they exist
      IntegrationAllowedPackage.where(repository_id: @actor.id, package_id: package.id, integration_id: integration.id).delete_all

      integration_allowed_packages.save!
    end

    redirect_to :back

  rescue ActiveRecord::RecordInvalid
    flash[:error] = "Can't grant permissions"
    redirect_to :back
  end

  def activate_action_package # rubocop:todo GitHub/UseRestfulActions
    unless package.can_activate_actions_package?(current_user)
      flash[:error] = "You cannot activate this Actions package."
      return redirect_to package_settings_path
    end

    begin
      PackageRegistry::Twirp.action_packages_client.activate_action_package_resolution(
        package_id: package.id
      )
      flash[:notice] = "Package activated. Semantic versioning references will now resolve to the versions from this package."
    rescue PackageRegistry::Twirp::BaseError => e
      Failbot.report(e)
      flash[:error] = "Actions package could not be activated. Please try again later."
    end

    redirect_to :back
  end

  def add_codespaces_access # rubocop:todo GitHub/UseRestfulActions
    unless actions_can_be_granted_permissions?
      flash[:error] = "Can't grant permissions to inaccessible repository."
      return redirect_to :back
    end

    # Clean up any old roles if they exist
    IntegrationAllowedPackage.where(repository_id: @actor.id, package_id: package.id, integration_id: integration.id).delete_all

    # Add read role as initial grant
    integration_allowed_packages = IntegrationAllowedPackage.new(
      repository_id: @actor.id,
      access_type: :contents,
      package_id: package.id,
      integration_id: integration.id
    )

    if integration_allowed_packages.save
      Packages::AppendPackageCodespacesPermissionsForRepositoryJob.perform_later(
        repository_id: @actor.id,
        package_id: package.id,
        user_id: current_user.id,
        entry_point: :registry_two_package_settings_controller_add_codespaces_access,
      )
      redirect_to :back
    else
      flash[:error] = "Can't grant permissions"
      redirect_to :back
    end
  end

  def update_collaborator # rubocop:todo GitHub/UseRestfulActions
    # If owner is an organization, verify actor is org member.
    unless actor_can_be_granted_permissions?
      flash[:error] = "Can't grant permissions to users who cannot access this organization."
      return redirect_to :back
    end

    role_to_grant = params.require(:permission)
    unless Role::PACKAGES_SYSTEM_ROLES.include?(role_to_grant)
      flash[:error] = "Can't grant permissions"
      return redirect_to :back
    end

    # Revoke all old roles
    Role.system_package_roles.each do |role|
      next if role.name == role_to_grant
      Permissions::Granters::RoleGranter.new(
        actor: actor, target: package, role: role
      ).revoke_if_exists!
    end

    # Grant the new role
    new_role = Role.internal_role_by_name(role_to_grant)
    result = Permissions::Granters::RoleGranter.new(
      actor: actor, target: package, role: new_role
    ).grant!

    if result.success?
      head :ok
    else
      head :forbidden
    end
  end

  def update_actions_access # rubocop:todo GitHub/UseRestfulActions
    unless actions_can_be_granted_permissions?
      flash[:error] = "Can't grant permissions to inaccessible repository."
      return redirect_to :back
    end

    role_to_grant = params.require(:permission)
    unless IntegrationAllowedPackage.access_types.include?(role_to_grant.to_sym)
      flash[:error] = "Can't grant permissions"
      return redirect_to :back
    end

    integration_allowed_packages = IntegrationAllowedPackage.new(repository_id: @actor.id, access_type: role_to_grant, package_id: package.id, integration_id: integration.id)

    IntegrationAllowedPackage.transaction do
      # Revoke all old roles
      IntegrationAllowedPackage.where(repository_id: @actor.id, package_id: package.id, integration_id: integration.id).delete_all

      # Add read role as initial grant
      integration_allowed_packages.save!
    end

    head :ok
  rescue ActiveRecord::RecordInvalid
    head :forbidden
  end

  def bulk_update_collaborators # rubocop:todo GitHub/UseRestfulActions
    role_to_grant = params.require(:role)
    unless Role::PACKAGES_SYSTEM_ROLES.include?(role_to_grant)
      flash[:error] = "Can't grant permissions"
      return redirect_to :back
    end

    new_role = T.must(Role.internal_role_by_name(role_to_grant))
    selected_members = fetch_members(params.require(:selected_ids))
    other_package_roles = Role.system_package_roles.where.not(id: new_role.id)

    # TODO(dinahshi): make this more performant by bulk fetching UserRoles and
    # skipping if member already has role_to_grant. OR put into background job.
    results = selected_members.each_with_object([]) do |actor, results|
      other_package_roles.each do |role|
        Permissions::Granters::RoleGranter.new(
          actor: actor, target: package, role: role
        ).revoke_if_exists!
      end

      results << Permissions::Granters::RoleGranter.new(
        actor: actor, target: package, role: new_role
      ).grant!.success?
    end

    if results.all?
      flash[:notice] = "Permissions updated for selected members."
    else
      flash[:notice] = "Something went wrong while bulk updating permissions."
    end

    redirect_to :back
  end

  def bulk_update_actions_access # rubocop:todo GitHub/UseRestfulActions
    role_to_grant = params.require(:role)

    unless IntegrationAllowedPackage.access_types.include?(role_to_grant.to_sym)
      flash[:error] = "Can't grant permissions"
      return redirect_to :back
    end

    repos = fetch_actions_access(params.require(:selected_ids))

    results = repos.each_with_object([]) do |actor, results|
      IntegrationAllowedPackage.transaction do
        # Revoke all old roles
        IntegrationAllowedPackage.where(repository_id: actor.id, package_id: package.id, integration_id: integration.id).delete_all

        IntegrationAllowedPackage.new(repository_id: actor.id, access_type: role_to_grant, package_id: package.id, integration_id: integration.id).save!

        results << true
      end
    rescue ActiveRecord::RecordInvalid
      results << false
    end

    if results.all?
      flash[:notice] = "Permissions updated for selected repositories."
    else
      flash[:notice] = "Something went wrong while bulk updating permissions."
    end

    redirect_to :back
  end

  def remove_collaborator # rubocop:todo GitHub/UseRestfulActions
    # Revoke all old roles
    Role.system_package_roles.each do |role|
      Permissions::Granters::RoleGranter.new(
        actor: actor, target: package, role: role
      ).revoke_if_exists!
    end

    respond_to do |wants|
      wants.html do
        if request.xhr?
          head :ok
        else
          username = actor.is_a?(User) ? actor.display_login : actor.name
          flash_message = "Removed #{username} as a package collaborator."
          redirect_to :back, flash: { notice: flash_message }
        end
      end
    end
  end

  def remove_actions_access # rubocop:todo GitHub/UseRestfulActions
    unless actions_can_be_granted_permissions?
      flash[:error] = "Can't change permissions to inaccessible repository."
      return redirect_to :back
    end

    # Revoke all old roles
    IntegrationAllowedPackage.where(repository_id: @actor.id, package_id: package.id, integration_id: integration.id).delete_all

    respond_to do |wants|
      wants.html do
        if request.xhr?
          head :ok
        else
          flash_message = "Removed access from repository #{@actor.name}."
          redirect_to :back, flash: { notice: flash_message }
        end
      end
    end
  end

  def remove_codespaces_access # rubocop:todo GitHub/UseRestfulActions
    unless actions_can_be_granted_permissions?
      flash[:error] = "Can't change permissions to inaccessible repository."
      return redirect_to :back
    end

    # Revoke all old roles
    IntegrationAllowedPackage.where(repository_id: @actor.id, package_id: package.id, integration_id: integration.id).delete_all
    Packages::RemovePackageCodespacesPermissionsForRepositoryJob.perform_later(
      repository_id: @actor.id,
      package_id: package.id,
      user_id: current_user.id,
      entry_point: :registry_two_package_settings_controller_remove_codespaces_access,
    )

    respond_to do |wants|
      wants.html do
        if request.xhr?
          head :ok
        else
          flash_message = "Removed access from repository #{@actor.name}."
          redirect_to :back, flash: { notice: flash_message }
        end
      end
    end
  end

  def collaborator_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "registry_two/package_settings/collaborator_suggestions", formats: :html, locals: { suggestions: filtered_suggestions }
      end
      format.html do
        render partial: "registry_two/package_settings/collaborator_suggestions", locals: { suggestions: filtered_suggestions }
      end
    end
  end

  def repository_suggestions # rubocop:todo GitHub/UseRestfulActions
    suggestions = package.owner.visible_repositories_for(current_user).where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%")
    respond_to do |format|
      format.html_fragment do
        render partial: "registry_two/package_settings/collaborator_suggestions", formats: :html, locals: { suggestions: suggestions }
      end
      format.html do
        render partial: "registry_two/package_settings/collaborator_suggestions", locals: { suggestions: suggestions }
      end
    end
  end

  def toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    selected_count = params[:selected_ids]&.count || 0

    respond_to do |format|
      format.html do
        render partial: "registry_two/package_settings/access_management/members_toolbar_actions", locals: { selected_count: selected_count, selected_ids: params[:selected_ids], members_count: members_to_roles.count  }
      end
    end
  end

  def repositories_toolbar_actions # rubocop:todo GitHub/UseRestfulActions
    selected_count = params[:selected_ids]&.count || 0

    respond_to do |format|
      format.html do
        render partial: "registry_two/package_settings/access_management/repositories_toolbar_actions", locals: { selected_count: selected_count, selected_ids: params[:selected_ids], repositories_count: actions_packages_permissions.count  }
      end
    end
  end

  def change_visibility # rubocop:todo GitHub/UseRestfulActions
    unless params[:name].casecmp?(params[:verify])
      flash[:error] = "You must type the name of the package to confirm."
      return redirect_to package_settings_path
    end

    visibility = params[:visibility]
    if visibility.blank?
      flash[:error] = "A visibility setting must be provided."
      return redirect_to package_settings_path
    end

    if visibility == "internal"
      if !package.members_can_publish_internal_packages?
        # This is when the org settings disable internal visibility
        flash[:error] = "Cannot set package visibility to internal. Setting is disabled by organization administrators."
        return redirect_to package_settings_path
      end
    end

    if visibility == "public" && !package.members_can_publish_public_packages?
      # Safety measure to protect against public when not enabled by the org.
      flash[:error] = "Cannot set package visibility to public."
      return redirect_to package_settings_path
    end

    begin
      client.update_package_visibility(
        ecosystem: package.package_type,
        namespace: package.namespace,
        name: package.name,
        visibility: visibility,
        actor: current_user,
      )
    rescue PackageRegistry::Twirp::PermissionDeniedError
      flash[:error] = "You do not have permission to change the visibility of this package. Please ensure you have correct permissions on the package and are a member of the organization."
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = "The package could not be updated. Please try again later."
    end

    redirect_to package_settings_path
  end

  def change_actions_package_sharing_policy # rubocop:todo GitHub/UseRestfulActions
    unless package.can_edit_actions_package_sharing_policy?
      flash[:error] = "You can not edit sharing policy setting."
      return redirect_to package_settings_path
    end

    sharing_policy = params[:actions_package_share_policy]

    if sharing_policy.blank?
      flash[:error] = "A sharing policy setting must be selected."
      return redirect_to package_settings_path
    end

    mapped_policy = package.sharing_policy_value(sharing_policy)
    if mapped_policy == ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_UNKNOWN
      flash[:error] = "A valid sharing policy setting must be selected."
      return redirect_to package_settings_path
    end

    begin
      PackageRegistry::Twirp.action_packages_client.update_action_package_resolution_settings(
          package_id: package.id,
          sharing_policy: mapped_policy,
          )
      flash[:notice] = "Sharing policy successfully updated"
    # Note right now this should never throw an PermissionDeniedError since we are not passing user to validate
    # Unlike update_package_visibility can make a private package public which needs authorization, and change_active_sync_perms happens to use the end point
    # If the above code is changed we can update this accordingly
    rescue PackageRegistry::Twirp::BaseError => e
      Failbot.report(e)
      flash[:error] = "Sharing policy could not be updated. Please try again later."
    end

    redirect_to package_settings_path
  end

  def change_active_sync_perms # rubocop:todo GitHub/UseRestfulActions
    active_sync_perms = params[:active_sync_perms]&.downcase == "true"

    begin
      client.update_package_active_sync_perms(
          ecosystem: package.package_type,
          namespace: package.namespace,
          name: package.name,
          active_sync_perms: active_sync_perms,
          actor: current_user,
          )
    rescue PackageRegistry::Twirp::PermissionDeniedError
      flash[:error] = "You do not have permission to change the visibility of this package. Please ensure you have correct permissions on the package."
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = "The package could not be updated. Please try again later."
    end

    if active_sync_perms && package.repository
      package.sync_access_from_repo(repository: package.repository)
    end

    redirect_to package_settings_path
  end

  def delete_package # rubocop:todo GitHub/UseRestfulActions
    unless params[:name].casecmp?(params[:verify])
      flash[:error] = "You must type the name of the package to confirm."
      return redirect_to package_settings_path
    end

    begin
      client.delete_package(
        ecosystem: package.package_type,
        namespace: package.namespace,
        name: package.name,
        actor: current_user,
        mode: :soft
      )
    rescue PackageRegistry::Twirp::FailedPreconditionError => e
      flash[:error] = e.msg.humanize
      return redirect_to package_settings_path
    rescue PackageRegistry::Twirp::BaseError
      flash[:error] = "The package could not be deleted. Please try again later."
      return redirect_to package_settings_path
    end

    # Delist an action package from marketplace if a package is deleted
    if GitHub.flipper[:action_package_marketplace].enabled?(current_user) && package.deleted?
      repository_action = RepositoryAction.listed.find_by(repository: package.repository)
      if repository_action.present? && repository_action.action_package_listed?
        repository_action.delisted!
      end
    end

    return redirect_to packages_path(package.repository.owner, package.repository) if package&.repository && !package&.repository.deleted?
    redirect_to packages_two_path
  end

  def actions_access # rubocop:todo GitHub/UseRestfulActions
    redirect_to package_settings_path
  end

  def ensure_v2_package # rubocop:todo GitHub/UseRestfulActions
    redirect_to package_two_path unless supported_v2_ecosystem(params[:ecosystem])
  end

  def load_actor_from_params # rubocop:todo GitHub/UseRestfulActions
    @actor_type, @actor_id = params[:collaborator]&.split("/", 2)

    unless @actor_type && @actor_id
      flash[:error] = "Can't grant permissions to unknown collaborator"
      return redirect_to :back
    end

    if UserRole::VALID_ACTOR_TYPES.include?(@actor_type.capitalize)
      @actor = if @actor_type == "team"
        Team.find_by(id: @actor_id)
      else
        User.find_by(id: @actor_id)
      end
    end

    unless @actor
      flash[:error] = "Can't grant permissions"
      redirect_to :back
    end
  end

  def load_repo_from_params # rubocop:todo GitHub/UseRestfulActions
    @actor_type, @actor_id = params[:collaborator]&.split("/", 2)

    unless @actor_type && @actor_id
      flash[:error] = "Can't grant permissions to unknown collaborator"
      return redirect_to :back
    end

    @actor = if @actor_type == "repository"
      Repository.find_by(id: @actor_id)
    end

    unless @actor
      flash[:error] = "Can't grant permissions"
      redirect_to :back
    end
  end

  def load_actions_integration # rubocop:todo GitHub/UseRestfulActions
    @integration = Apps::Privileged.integration(:actions)

    unless @integration
      flash[:error] = "Can't grant permissions"
      redirect_to :back
    end
  end

  def load_codespace_integration # rubocop:todo GitHub/UseRestfulActions
    @integration = Apps::Privileged.integration(:codespaces_production)

    unless @integration
      flash[:error] = "Can't grant permissions"
      redirect_to :back
    end
  end

  def fetch_members(member_strings) # rubocop:todo GitHub/UseRestfulActions
    user_ids, team_ids = [], []
    member_strings.each do |member_string|
      member_type, member_id = member_string.split("/", 2)
      next unless UserRole::VALID_ACTOR_TYPES.include?(member_type.capitalize)

      if member_type == "team"
        team_ids << member_id.to_i
      else
        user_ids << member_id.to_i
      end
    end

    # If this is an org owned package, ensure all users and teams are members
    # of the organization.
    if owner.is_a?(Organization)
      user_ids = user_ids & owner.members.pluck(:id)
      team_ids = team_ids & owner.visible_teams_for(current_user).pluck(:id)
    else
      team_ids = []
    end

    User.where(id: user_ids) + Team.where(id: team_ids)
  end

  def fetch_actions_access(repo_ids) # rubocop:todo GitHub/UseRestfulActions
    repo_ids = repo_ids.map(&:to_i).compact

    Repository.where(id: repo_ids).select { |repo| repo.readable_by?(current_user) }
  end

  def actor_can_be_granted_permissions? # rubocop:todo GitHub/UseRestfulActions
    return false if owner.user? && actor.instance_of?(Team)
    return true unless owner.is_a?(Organization)

    if actor.is_a?(User)
      owner.readable_by?(actor)
    else
      owner.visible_teams_for(current_user).pluck(:id).include?(actor.id)
    end
  end

  def actions_can_be_granted_permissions? # rubocop:todo GitHub/UseRestfulActions
    return false unless actor.instance_of?(Repository)

    actor.readable_by?(current_user)
  end

  def actions_packages_permissions # rubocop:todo GitHub/UseRestfulActions
    integration = Apps::Privileged.integration(:actions)
    return IntegrationAllowedPackage.none if integration.blank?

    actions_allowed_repos = IntegrationAllowedPackage.where(package_id: package.id, integration_id: integration.id).joins(:repository).where(repositories: { active: true })
    visible_repo_ids = package.owner.visible_repositories_for(current_user).pluck(:id)
    actions_allowed_repos.filter { |repo| visible_repo_ids.include?(repo.repository_id) }
  end

  def codespaces_packages_permissions # rubocop:todo GitHub/UseRestfulActions
    return IntegrationAllowedPackage.none if GitHub.enterprise?

    integration = Apps::Privileged.integration(:codespaces_production)
    return IntegrationAllowedPackage.none if integration.blank?

    codespaces_allowed_repos = IntegrationAllowedPackage.where(package_id: package.id, integration_id: integration.id).joins(:repository).where(repositories: { active: true })
    visible_repo_ids = package.owner.visible_repositories_for(current_user).pluck(:id)
    codespaces_allowed_repos.filter { |repo| visible_repo_ids.include?(repo.repository_id) }
  end

  def filtered_suggestions # rubocop:todo GitHub/UseRestfulActions
    autocompleteQuery = if owner.is_a?(Organization)
      AutocompleteQuery.new(current_user, params[:q],
        organization: owner,
        include_teams: true,
        org_members_only: true,
      )
    else
      AutocompleteQuery.new(current_user, params[:q])
    end

    autocompleteQuery.suggestions - members_to_roles.keys
  end

  def bulk_add_actions_access# rubocop:todo GitHub/UseRestfulActions
    if params[:repo_name].present?
      # Since repo names are not globally unique we need to scope to a owner.
      # The UI only allows searching for repositories that are owned by the owner of the package.
      # Including the `owner` here as `package.owner` ensures that we never
      # assign a repo not owned by the package owner.
      repo = Repository.find_by(owner: package.owner, name: params[:repo_name])
      repos = repo.present? ? [repo] : []
    else
      selected_ids = params.require(:selected_ids).split(",")
      repos = fetch_actions_access(selected_ids)
    end

    results = repos.each_with_object([]) do |actor, results|

      IntegrationAllowedPackage.transaction do

        # Add read role as initial grant
        integration_allowed_packages = IntegrationAllowedPackage.new(repository_id: actor.id, access_type: "contents", package_id: package.id, integration_id: integration.id)
        # Revoke all old roles
        IntegrationAllowedPackage.where(repository_id: actor.id, package_id: package.id, integration_id: integration.id).delete_all

        integration_allowed_packages.save!

        results << true
      end
    rescue ActiveRecord::RecordInvalid
      results << false
    end

    if results.all?
      flash[:notice] = "Permissions added for selected repositories."
    else
      flash[:notice] = "Something went wrong while bulk adding permissions."
    end

    redirect_to :back
  end

  def repository_list# rubocop:todo GitHub/UseRestfulActions
    repositories = package.owner.visible_repositories_for(current_user)
    access_type = params[:access_type].downcase.to_sym if params[:access_type].present?
    repo_ids = []
    repo_ids = actions_packages_permissions.pluck(:repository_id) || [] if access_type == :actions
    repo_ids = codespaces_packages_permissions.pluck(:repository_id) || [] if access_type == :codespaces
    if repo_ids.size > 0
      repositories = repositories.filter { |repo| !repo_ids.include?(repo.id) }
    end
    render json: { repositories: repositories.map { |r| { id: r.id, name: r.repo_type_icon == "repo-forked" ? r.name_with_display_owner : r.name, repo_type_icon: r.repo_type_icon } } }
  end

  def bulk_add_codespaces_access# rubocop:todo GitHub/UseRestfulActions
    selected_ids = params.require(:selected_ids).split(",")
    repos = fetch_actions_access(selected_ids)

    results = repos.each_with_object([]) do |actor, results|

      IntegrationAllowedPackage.transaction do

        # Add read role as initial grant
        integration_allowed_packages = IntegrationAllowedPackage.new(repository_id: actor.id, access_type: "contents", package_id: package.id, integration_id: integration.id)
        # Revoke all old roles
        IntegrationAllowedPackage.where(repository_id: actor.id, package_id: package.id, integration_id: integration.id).delete_all

        integration_allowed_packages.save!
      end

      Packages::AppendPackageCodespacesPermissionsForRepositoryJob.perform_later(
        repository_id: actor.id,
        package_id: package.id,
        user_id: current_user.id,
        entry_point: :registry_two_package_settings_controller_bulk_add_codespaces_access,
      )

      results << true
    rescue ActiveRecord::RecordInvalid
      results << false
    end

    if results.all?
      flash[:notice] = "Permissions added for selected repositories."
    else
      flash[:notice] = "Something went wrong while bulk adding permissions."
    end

    redirect_to :back
  end

  def toggle_list_action_package# rubocop:todo GitHub/UseRestfulActions
    repository_action = RepositoryAction.find_by(repository: package.repository)

    if repository_action.present?
      if repository_action.action_package_listed? && repository_action.state == "listed"
        repository_action.delisted!
        flash[:notice] = "Delisted from marketplace"
      else
        begin
          client.retire_namespace(
            namespace: package.namespace,
            name: package.name,
            ecosystem: package.package_type,
            owner_id: owner.id
          )
        rescue PackageRegistry::Twirp::InvalidArgumentError
          flash[:notice] = "The namespace already retired."
        rescue PackageRegistry::Twirp::ServiceUnavailableError
          flash[:error] = "The namespace could not be retired. Please try again later."
          redirect_to :back and return
        end

        if T.must(T.must(repository_action.repository).owner).organization?
          update_contact_email_for_org(repository_action)
        end
        repository_action.list_action_package_on_marketplace
        flash[:notice] = "Listed to marketplace"
      end
    else
      flash[:error] = "Action not found"
    end

    redirect_to :back
  end

  def update_action_category_contact_email# rubocop:todo GitHub/UseRestfulActions
    repository_action = RepositoryAction.find_by(repository: package.repository)

    update_action_categories(repository_action)

    if T.must(T.must(T.must(repository_action).repository).owner).organization?
      update_contact_email_for_org(repository_action)
    end

    T.must(repository_action).save!

    redirect_to :back
  end

  def verify_email_format# rubocop:todo GitHub/UseRestfulActions
    security_contact_email = params[:value]

    if !security_contact_email.blank? && security_contact_email =~ URI::MailTo::EMAIL_REGEXP
      respond_to do |format|
        format.html_fragment do
          head 200
        end
      end
    else
      respond_to do |format|
        format.html_fragment do
          render body: "Email is invalid", status: 422, content_type: "text/fragment+html"
        end
      end
    end
  end

  private

  def update_contact_email_for_org(repository_action)
    contact_email = params[:contact_email]

    if !contact_email.nil? && contact_email.empty?
      flash[:notice] = "Contact email can't be blank"
    elsif repository_action.security_email.nil?
      repository_action.security_email = current_user.email
    elsif contact_email && contact_email != repository_action.security_email
      repository_action.security_email = contact_email
    end
  end

  def update_action_categories(repository_action)
    categories = []

    first_category = params[:primary_category_id]
    second_category = params[:secondary_category_id]

    if !first_category.nil?
      categories << first_category
    end

    if !second_category.nil?
      categories << second_category if second_category != categories.first
    end

    if repository_action && categories.any?
      filter_categories = repository_action.filter_category_ids
      repository_action.category_ids = categories + filter_categories
    else
      flash[:notice] = "No categories selected"
    end
  end
end
