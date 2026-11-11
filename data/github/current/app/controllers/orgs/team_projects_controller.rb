# typed: false
# frozen_string_literal: true

class Orgs::TeamProjectsController < Orgs::Controller
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  layout "team"

  before_action :render_404_unless_projects_classic_ui_enabled_for_current_user
  before_action :login_required
  before_action :this_team_required
  before_action :admin_on_team_required, except: [:index, :update, :destroy, :suggestions]
  before_action :set_team_context_crumb, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PROJECT_PAGE_SIZE = 30

  IndexQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($login: String!, $slug: String!, $first: Int, $last: Int, $before: String, $after: String) {
      organization(login: $login) {
        ...Views::Orgs::TeamProjects::Index::Organization
      }
    }
  GRAPHQL

  def index
    variables = graphql_pagination_params(page_size: PROJECT_PAGE_SIZE).merge(
      login: params[:org],
      slug: params[:team_slug],
    )

    data = platform_execute(IndexQuery, variables: variables)

    respond_to do |format|
      format.html do
        render "orgs/team_projects/index", locals: {
          graphql_org: data.organization,
          selected_nav_item: :projects,
          show_templates_index: true,
        }
      end
    end
  end

  CreateQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!) {
      addTeamProject(input: { projectId: $projectId, teamId: $teamId }) {
        __typename # A selection is grammatically required here
      }
    }
  GRAPHQL

  def create
    variables = {
      projectId: params[:project_id],
      teamId: this_team.global_relay_id,
    }

    data = platform_execute(CreateQuery, variables: variables)

    if data.errors.any?
      flash[:error] = data.errors.all.values.flatten.first
    else
      flash[:notice] = "The project was added to this team."
    end

    respond_to do |format|
      format.html do
        redirect_to team_projects_path(this_organization, this_team)
      end
    end
  end

  UpdateQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!, $permission: ProjectPermission!) {
      updateTeamProject(input: { projectId: $projectId, teamId: $teamId, permission: $permission }) {
        __typename # A selection is grammatically required here
      }
    }
  GRAPHQL

  def update
    project = this_organization.visible_projects_for(current_user).find(params[:project_id])
    variables = {
      projectId: project.global_relay_id,
      teamId: this_team.global_relay_id,
      permission: params[:permission].upcase,
    }

    data = platform_execute(UpdateQuery, variables: variables)

    respond_to do |format|
      format.html do
        if data.errors.any?
          flash[:error] = data.errors.all.values.flatten
        else
          flash[:notice] = "The team's permission on the project was updated to '#{params[:permission]}'."
        end

        redirect_to team_projects_path(this_organization, this_team)
      end

      format.json do
        if data.errors.any?
          head 401
        else
          head 201
        end
      end
    end
  end

  DestroyQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    mutation($projectId: ID!, $teamId: ID!) {
      removeTeamProject(input: { projectId: $projectId, teamId: $teamId }) {
        __typename # A selection is grammatically required here
      }
    }
  GRAPHQL

  def destroy
    project = this_organization.visible_projects_for(current_user).find(params[:project_id])
    variables = {
      projectId: project.global_relay_id,
      teamId: this_team.global_relay_id,
    }

    data = platform_execute(DestroyQuery, variables: variables)

    respond_to do |format|
      format.html do
        if data.errors.any?
          flash[:error] = data.errors.all.values.flatten
        else
          flash[:notice] = "The project has been removed from the team."
        end

        redirect_to team_projects_path(this_organization, this_team)
      end

      format.json do
        if data.errors.any?
          head 401
        else
          head 201
        end
      end
    end
  end

  SuggestionsQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
    query($login: String!, $slug: String!, $first: Int!, $search: String) {
      organization(login: $login) {
        ...Views::Orgs::TeamProjects::Suggestions::Organization
      }
    }
  GRAPHQL

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    variables = {
      login: params[:org],
      slug: params[:team_slug],
      first: 10,
      search: params[:q],
    }

    data = platform_execute(SuggestionsQuery, variables: variables)

    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/team_projects/suggestions", formats: :html, locals: {
          graphql_org: data.organization,
        }
      end
    end
  end
end
