# typed: false
# frozen_string_literal: true

class ProjectSettingsController < ApplicationController
  include EnterpriseManagedUsersHelper
  include OrganizationParamsHelper
  include PlatformHelper
  include SharedProjectControllerActions

  before_action :require_projects_enabled
  before_action :hide_spammy_projects
  before_action :org_project_required, only: [:teams, :team_results, :add_team, :update_team, :remove_team]
  before_action :this_project_required
  before_action :org_membership_required
  before_action :project_admin_required, except: [:admins, :linked_repositories, :link_repository, :unlink_repository]
  before_action :project_write_required, only: [:admins, :linked_repositories, :link_repository, :unlink_repository]

  layout :org_or_user_project
  javascript_bundle :settings
  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:admins]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:linked_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:team_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:teams]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:users]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :admins, :users, :teams, :team_results, :linked_repositories],
    optional: true

  IndexQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::Index::ProjectOwner
      }
    }
  GRAPHQL

  def index
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
    }

    data = platform_execute(IndexQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html do
          render "project_settings/index", locals: {
            project_owner: project_owner,
            public_project_description: public_project_description,
            public_project_label: public_project_label,
            this_project: this_project,
          }
        end
      end
    else
      render_404
    end
  end

  AdminsQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::Admins::ProjectOwner
      }
    }
  GRAPHQL

  def admins # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
    }

    data = platform_execute(AdminsQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html do
          render "project_settings/admins", locals: { project_owner: project_owner, this_project: this_project }
        end
      end
    else
      render_404
    end
  end

  UsersQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::Users::ProjectOwner
      }

      viewer {
        ...Views::ProjectSettings::Users::Viewer
      }
    }
  GRAPHQL

  def users # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
    }

    data = platform_execute(UsersQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html do
          render "project_settings/users", locals: {
            project_owner: project_owner,
            viewer: data.viewer,
            this_project: this_project,
          }
        end
      end
    else
      render_404
    end
  end

  TeamsQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!, $query: String) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::Teams::ProjectOwner
      }
    }
  GRAPHQL

  def teams # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
    }

    data = platform_execute(TeamsQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html do
          render "project_settings/teams", locals: { project_owner: project_owner, this_project: this_project }
        end
      end
    else
      render_404
    end
  end

  LinkedRepositoriesQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::LinkedRepositories::ProjectOwner
      }
    }
  GRAPHQL

  def linked_repositories # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
    }

    data = platform_execute(LinkedRepositoriesQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html do
          render "project_settings/linked_repositories", locals: {
            project_owner: project_owner,
            this_project: this_project
          }
        end
      end
    else
      render_404
    end

  end

  TeamResultsQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($projectOwnerId: ID!, $projectNumber: Int!, $query: String) {
      node(id: $projectOwnerId) {
        ...Views::ProjectSettings::TeamResults::ProjectOwner
      }
    }
  GRAPHQL

  def team_results # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectOwnerId: this_user.global_relay_id,
      projectNumber: params[:project_number].to_i,
      query: params[:q].to_s,
    }

    data = platform_execute(TeamResultsQuery, variables: variables)

    if project_owner = data.node
      respond_to do |format|
        format.html_fragment do
          render partial: "project_settings/team_results", formats: :html, locals: { project_owner: project_owner }
        end
      end
    else
      render_404
    end
  end

  UpdateQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $public: Boolean!) {
      updateProject(input: { projectId: $projectId, public: $public }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def update
    make_public = params[:project][:public] == "true"

    variables = {
      projectId: this_project.global_relay_id,
      public: make_public,
    }

    data = platform_execute(UpdateQuery, variables: variables)

    if data.errors.all.any?
      flash[:error] = "There was an error while trying to make this project #{make_public ? "public" : "private"}."
    else
      flash[:notice] = "This project is now #{make_public ? "public" : "private"}."
    end

    redirect_to project_settings_path(this_project)
  end

  UpdateOrgQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $organizationPermission: ProjectPermission!) {
      updateProject(input: { projectId: $projectId, organizationPermission: $organizationPermission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def update_org # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectId: this_project.global_relay_id,
      organizationPermission: params[:permission].upcase,
    }

    data = platform_execute(UpdateOrgQuery, variables: variables)

    if data.errors.all.any?
      flash[:error] = "There was an error trying to update this project's organization-wide permission."
    elsif params[:permission] == "none"
      flash[:notice] = "Removed organization-wide permission"
    else
      flash[:notice] = "Updated organization-wide permission to #{params[:permission]}"
    end

    check_permission_and_redirect_to project_settings_path(this_project)
  end

  AddTeamQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!) {
      addTeamProject(input: { projectId: $projectId, teamId: $teamId }) {
        projectTeamEdge {
          ...Views::ProjectSettings::Team::ProjectTeamEdge
        }
      }
    }
  GRAPHQL

  def add_team # rubocop:todo GitHub/UseRestfulActions
    if team = this_user.visible_teams_for(current_user).find_by(id: params[:team])
      variables = {
        projectId: this_project.global_relay_id,
        teamId: team.global_relay_id,
      }

      data = platform_execute(AddTeamQuery, variables: variables)

      respond_to do |format|
        format.html do
          if data.errors.all.any?
            flash[:error] = "Error adding #{team} to this project"
          else
            flash[:notice] = "Added #{team} to this project"
          end

          redirect_to project_settings_teams_path(this_project.owner, this_project)
        end

        format.json do
          payload = if data.errors.all.any?
            { error: "Error adding #{team} to this project" }
          else
            {
              name: team.name,
              html: render_to_string(
                partial: "project_settings/team",
                formats: [:html],
                locals: { team_edge: data.add_team_project.project_team_edge },
              ),
            }
          end

          render json: payload
        end
      end
    else
      error = "Invalid team id: #{params[:team_id]}"

      respond_to do |format|
        format.html do
          flash[:error] = error

          redirect_to project_settings_teams_path(this_project.owner, this_project)
        end

        format.json do
          render json: { error: error }
        end
      end
    end
  end

  UpdateTeamQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!, $permission: ProjectPermission!) {
      updateTeamProject(input: { projectId: $projectId, teamId: $teamId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def update_team # rubocop:todo GitHub/UseRestfulActions
    team = Team.find_by_id(params[:team_id])

    variables = {
      projectId: this_project.global_relay_id,
      teamId: team&.global_relay_id,
      permission: params[:permission].upcase,
    }

    data = platform_execute(UpdateTeamQuery, variables: variables)

    respond_to do |format|
      format.html do
        if data.errors.all.any?
          flash[:error] = "Error updating team's permission on this project"
        else
          flash[:notice] = "Updated #{team}'s permission on this project to #{params[:permission].inspect}"
        end

        check_permission_and_redirect_to project_settings_teams_path(this_project.owner, this_project)
      end

      format.json do
        if data.errors.all.any?
          head 401
        else
          render json: { permission: params[:permission] }
        end
      end
    end
  end

  RemoveTeamQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!) {
      removeTeamProject(input: { projectId: $projectId, teamId: $teamId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def remove_team # rubocop:todo GitHub/UseRestfulActions
    team = Team.find_by_id(params[:team_id])

    variables = {
      projectId: this_project.global_relay_id,
      teamId: team&.global_relay_id,
    }

    data = platform_execute(RemoveTeamQuery, variables: variables)

    respond_to do |format|
      format.html do
        if data.errors.all.any?
          flash[:error] = "Error removing team from this project"
        else
          flash[:notice] = "Removed #{team} from this project"
        end

        check_permission_and_redirect_to project_settings_teams_path(this_project.owner, this_project)
      end

      format.json do
        if data.errors.all.any?
          head 401
        else
          head 201
        end
      end
    end
  end

  AddUserQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $userId: ID!) {
      addProjectCollaborator(input: { projectId: $projectId, userId: $userId }) {
        projectUserEdge {
          ...Views::ProjectSettings::User::ProjectUserEdge
        }
      }
    }
  GRAPHQL

  AddUserViewerQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query {
      viewer {
        ...Views::ProjectSettings::User::Viewer
      }
    }
  GRAPHQL

  def add_user # rubocop:todo GitHub/UseRestfulActions
    if user = User.find_by(login: params[:member])
      if user.blocked_by?(this_project.owner)
        # Do not reveal that the user is blocked. Generic error message is enough.
        error = "Unable to add: @#{params[:member]}"

        respond_to do |format|
          format.html do
            flash[:error] = "Unable to add: @#{params[:member]}"

            redirect_to project_settings_users_path(this_project)
          end

          format.json do
            render json: { error: error }
          end
        end
        return
      end

      variables = {
        projectId: this_project.global_relay_id,
        userId: user.global_relay_id,
      }

      data = platform_execute(AddUserQuery, variables: variables)

      respond_to do |format|
        format.html do
          if data.errors.all.any?
            flash[:error] = data.errors.all.values.flatten.join("\n")
          else
            flash[:notice] = "Added #{user.display_login} to this project"
          end
          redirect_to project_settings_users_path(this_project)
        end

        format.json do
          payload = if data.errors.all.any?
            { error: data.errors.all.values.flatten.join("\n") }
          else
            viewer_data = platform_execute(AddUserViewerQuery)

            {
              html: render_to_string(
                partial: "project_settings/user",
                formats: [:html],
                locals: {
                  collaborator_edge: data.add_project_collaborator.project_user_edge,
                  viewer: viewer_data.viewer,
                },
              ),
            }
          end

          render json: payload
        end
      end
    else
      error = "Invalid user: @#{params[:member]}"

      respond_to do |format|
        format.html do
          flash[:error] = "Invalid user: @#{params[:member]}"

          redirect_to project_settings_users_path(this_project)
        end

        format.json do
          render json: { error: error }
        end
      end
    end
  end

  UpdateUserQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $userId: ID!, $permission: ProjectPermission!) {
      updateProjectCollaborator(input: { projectId: $projectId, userId: $userId, permission: $permission }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def update_user # rubocop:todo GitHub/UseRestfulActions
    if user = User.find_by(id: params[:collaborator_id])
      variables = {
        projectId: this_project.global_relay_id,
        userId: user.global_relay_id,
        permission: params[:permission].upcase,
      }

      data = platform_execute(UpdateUserQuery, variables: variables)

      respond_to do |format|
        format.html do
          if data.errors.all.any?
            flash[:error] = data.errors.all.values.flatten.join("\n")
          else
            flash[:notice] = "Updated #{user.display_login}'s permission on this project to #{params[:permission].inspect}"
          end

          check_permission_and_redirect_to project_settings_users_path(this_project)
        end

        format.json do
          if data.errors.all.any?
            head 401
          else
            render json: { permission: params[:permission] }
          end
        end
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Invalid user id: #{params[:user_id]}"

          check_permission_and_redirect_to project_settings_users_path(this_project)
        end

        format.json do
          head 404
        end
      end
    end
  end

  RemoveUserQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $userId: ID!) {
      removeProjectCollaborator(input: { projectId: $projectId, userId: $userId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def remove_user # rubocop:todo GitHub/UseRestfulActions
    if user = User.find_by(id: params[:collaborator_id])
      variables = {
        projectId: this_project.global_relay_id,
        userId: user.global_relay_id,
      }

      data = platform_execute(RemoveUserQuery, variables: variables)

      respond_to do |format|
        format.html do
          if data.errors.all.any?
            flash[:error] = data.errors.all.values.flatten.join("\n")
          else
            flash[:notice] = "Removed #{user.display_login} from this project"
          end

          check_permission_and_redirect_to project_settings_users_path(this_project)
        end

        format.json do
          if data.errors.all.any?
            head 401
          else
            head 201
          end
        end
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = "Invalid user id: #{params[:user_id]}"

          check_permission_and_redirect_to project_settings_users_path(this_project)
        end

        format.json do
          head 404
        end
      end
    end
  end

  LinkRepositoryQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $repositoryId: ID!) {
      linkRepositoryToProject(input: { projectId: $projectId, repositoryId: $repositoryId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def link_repository # rubocop:todo GitHub/UseRestfulActions
    repo = this_user.find_repo_by_name(linked_repository_params[:repository_name])

    if repo&.readable_by?(current_user)
      variables = {
        projectId: this_project.global_relay_id,
        repositoryId: repo.global_relay_id,
      }
      mutation = platform_execute(LinkRepositoryQuery, variables: variables)

      if mutation.errors.any?
        flash[:error] = mutation.errors.messages.values.join(", ")
      else
        flash[:notice] = "Repository linked."
      end
    else
      flash[:error] = "Repository not found."
    end

    redirect_to project_settings_linked_repositories_path(this_project)
  end

  UnlinkRepositoryQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $repositoryId: ID!) {
      unlinkRepositoryFromProject(input: { projectId: $projectId, repositoryId: $repositoryId }) {
        __typename # a selection is grammatically required here
      }
    }
  GRAPHQL

  def unlink_repository # rubocop:todo GitHub/UseRestfulActions
    variables = {
      projectId: linked_repository_params[:project_global_id],
      repositoryId: linked_repository_params[:repository_global_id],
    }
    mutation = platform_execute(UnlinkRepositoryQuery, variables: variables)

    if mutation.errors.any?
      flash[:error] = "Uh oh! Something went wrong."
    else
      flash[:notice] = "Repository unlinked."
    end

    redirect_to project_settings_linked_repositories_path(this_project)
  end

  private

  def org_or_user_project
    if this_project.owner.is_a?(Organization)
      "layouts/org_projects"
    else
      "layouts/user_projects"
    end
  end

  memoize def this_user
    login_param = org_login_param || params[:user_id]
    User.find_by_login(login_param)
  end
  helper_method :this_user

  def this_organization
    this_user if this_user&.organization?
  end
  helper_method :this_organization

  private def disable_visibility_section?
    !this_project.viewer_can_change_visibility?(current_user)
  end
  helper_method :disable_visibility_section?

  memoize def this_project
    # We don't load through visible_projects_for here, since permissions are
    # checked in before_actions.
    this_user&.projects&.find_by_number!(params[:project_number])
  end
  helper_method :this_project

  def project_admin_required
    return true if this_project.adminable_by?(current_user)

    if this_project.writable_by?(current_user)
      redirect_to project_settings_admins_path(this_user, this_project)
    else
      render_404
    end
  end

  def project_write_required
    return render_404 unless this_project.writable_by?(current_user)
  end

  def org_project_required
    render_404 unless this_project&.owner_type == "Organization"
  end

  # We don't want to show any settings pages to collaborators because they don't
  # have sufficient access to org resources (teams, repos, etc) to warrant access
  # to the project settings page.
  # External collaborators can't see the menu in the UI because we check if *all*
  # org projects are writable and not this specific project.
  def org_membership_required
    return unless this_project.owner_type == "Organization"
    render_404 unless this_organization&.direct_member?(current_user)
  end

  def this_project_required
    return render_404 unless this_project
    render_404 if this_project.owner.is_a?(Repository)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  def check_permission_and_redirect_to(path)
    if this_project.adminable_by?(current_user)
      redirect_to path
    elsif this_project.readable_by?(current_user)
      redirect_to project_path(this_project)
    else
      # This looks like it could expose the existence of a private project, but
      # that should never actually happen. This method is meant to check
      # permissions _after_ a mutation has been successfully run. This means
      # the user already made it past project_admin_required, so they were
      # aware of the project's existence at the beginning of the controller
      # action.
      redirect_to projects_path({ type: "classic" }, owner: this_project.owner)
    end
  end

  def linked_repository_params
    params.require(:project_repository_link).permit(:project_global_id, :repository_name, :repository_global_id)
  end

  def public_project_label
    "public"
  end

  def public_project_description
    if GitHub.enterprise?
      "Anyone with access to your GitHub Enterprise Server instance can see this project. You choose who can make changes."
    else
      "Anyone on the internet can see this project. You choose who can make changes."
    end
  end
end
