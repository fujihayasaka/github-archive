# typed: true
# frozen_string_literal: true

# Team level memexes are actually a curation of org/user memexes. That means they represent a filtered view over the owner's (org) memex projects
# The "curation" relationship is retained using the MemexProjectLinks model
# This controller is just facilitating queries over the MemexProjectLinks model

class Orgs::TeamMemexesController < Orgs::Controller
  layout "team"

  include MemexesHelper
  include Memexes::ProjectListDependency
  include Memexes::ProjectLinkDependency
  include Memexes::GrantRoleOnCreateDependency
  include Memexes::SharedMemexesControllerActions


  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::TeamMemexesController#update",
    "Orgs::TeamMemexesController#create",
    "Orgs::TeamMemexesController#delete",
    "Orgs::TeamMemexesController#stats",
    "Orgs::TeamMemexesController#copy",
    "Orgs::TeamMemexesController#update_project_links",
    "Orgs::TeamMemexesController#upsert_team_project"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex

  before_action :login_required
  before_action :this_team_required
  before_action :set_team_context_crumb, only: [:index]
  before_action :team_admin_or_project_admin_required, only: [:update_project_links]
  before_action :team_admin_or_team_org_member_required, except: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:index]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries, only: [:index], optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :update_project_links, :upsert_team_project], optional: true

  javascript_bundle :"memex-index", only: [:index]

  def index
    # For pagination we just want to render the items and return these to the view
    return render Memex::ProjectList::ItemsContainerComponent.new(
      **list_projects(xhr: true).merge({ is_recent_selected: false, team: this_team })
    ), layout: false, locals: { page_title: "Projects" } if request&.xhr?

    list_projects_locals = list_projects("index")

    return redirect_to team_projects_beta_path(params: {
        query: Search::Queries::MemexProjectQuery::DEFAULT_QUERY,
        type: "new"
      }), status: 307 if list_projects_locals.nil?

    render "orgs/team_memexes/index", locals: { **list_projects_locals.merge({
      organization: this_organization,
      team: this_team,
      selected_nav_item: :projects
    }) }
  end

  depends_on_clusters ApplicationRecord::Collab, only: [:projects_suggestions]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql2, only: [:projects_suggestions], optional: true

  def projects_suggestions # rubocop:todo GitHub/UseRestfulActions
    only_memex_templates = params[:filter] == "templates"
    scope = params[:scope].presence || (params.include?(:q) && params[:q].blank? ? "recent" : nil)

    suggestions = project_suggestions(
      scope,
      this_team,
      only_memex_templates: only_memex_templates,
      min_permission_level: "admin",
      q: params[:q],
      limit: 200
    )

    respond_to do |format|
      format.json { render(json: suggestions) }
      format.any(:html, :html_fragment) do
        render(
          "orgs/team_memexes/projects_suggestions",
          layout: false,
          locals: { suggestions: suggestions },
          formats: [:html, :html_fragment]
        )
      end
    end
  end

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Repositories, only: [:upsert_team_project]

  # Project columns backed by issue fields need to query the issues and pull requests cluster to denormalize
  # the issue field values into the project columns.
  depends_on_clusters ApplicationRecord::IssuesPullRequests, only: [:upsert_team_project]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2, only: [:upsert_team_project], optional: true

  def upsert_team_project # rubocop:todo GitHub/UseRestfulActions
    if params[:action_type] == "create"
      create do |memex|
        # Upon Memex being created, publish the memex_event Hydro event
        publish_team_project_event("team_create", memex: memex, team: this_team)
      end
    elsif params[:action_type] == "link"
      update_project_links
    else
      redirect_back_or_to redirect_path
    end
  end

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Repositories, only: [:update_project_links]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2, only: [:update_project_links], optional: true

  def update_project_links # rubocop:todo GitHub/UseRestfulActions
    return redirect_back_or_to redirect_path if update_links_params.nil? || update_links_params.empty?

    operations = { link: [], unlink: [] }
    errors = []
    flash[:error] = ""

    memex_owner.memex_projects.where(number: update_links_params.keys.map(&:to_i)).each do |memex|
      if memex.viewer_is_admin?(current_user)
        operations[update_links_params[memex.number.to_s] == "on" ? :link : :unlink] << memex
      else
        flash[:error] += " " unless flash[:error].present?
        flash[:error] += "You must have admin permission on the project #{GitHub.url}#{memex.url} to add/remove it from this team."
      end
    end

    operations[:link].each do |memex|
      memex_path = "#{GitHub.url}#{memex.url}"
      begin
        memex.grant_role(this_team, "project_reader")
        publish_team_project_event("team_link_add", memex: memex, team: this_team)
        flash["memex_#{memex.number}"] = {
          "message" => "#{this_team.name} has been added as a collaborator to the project #{memex.title} with read permissions.",
          "link" => {
            "label" => "Manage access",
            "href" => memex_path + "/settings/access"
          }
        }

      rescue ArgumentError, Permissions::Granters::RoleGranter::GrantFailure
        errors << memex_path
      end
    end

    unless operations[:unlink].empty?
      operations[:unlink].each do |memex|
        failed = memex.remove_collaborator(this_team)
        publish_team_project_event("team_link_remove", memex: memex, team: this_team)
        errors << "#{GitHub.url}#{memex.url}" unless failed.empty?
      end
    end

    unless errors.empty?
      flash[:error] += " " unless flash[:error].present?
      flash[:error] += "An error occurred while adding or removing the following projects: " + \
        errors.map { |url| "#{url}" }.join(", ") + ". Please try again."
    end

    redirect_back_or_to redirect_path
  end

  private

  def source
    this_team
  end

  def load_more_path
    team_projects_beta_path
  end

  def redirect_path # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @redirect_path ||= team_projects_beta_path
  end

  def memex_owner
    this_team.owner
  end

  def update_links_params
    params.to_unsafe_h.with_indifferent_access[:projects_changes]
  end

  def publish_team_project_event(name, memex: nil, team: nil)
    GlobalInstrumenter.instrument("memex_event",
      {
        actor: current_user,
        memex_project: memex,
        memex_project_column: nil,
        memex_project_item: nil,
        name: name,
        ui: nil,
        context: {
          team_name: "#{team.name}",
        }.to_json,
        memex_project_view: nil
      }
    )
  end

  sig { override.params(memex: MemexProject).returns(T::Boolean) }
  def grant_role_on_create(memex)
    begin
      memex.grant_role(current_user, :admin)
      memex.grant_role(this_team, :writer)
      memex.update_organization_wide_role("project_reader", current_user)
      true
    rescue Permissions::Granters::RoleGranter::GrantFailure
      memex.destroy!
      render(json: { errors: ["Error occured when creating project"] }, status: :unprocessable_entity)
      false
    end
  end

  memoize def project_admin?
    memex_owner.accessible_memexes_scope(memex_owner.memex_projects.open_projects, current_user, "admin").exists?
  end

  def team_admin_or_team_org_member_required
    return render_404 if this_organization.nil?

    render_404 unless (this_team.member?(current_user) && memex_owner.member?(current_user)) || this_team.adminable_by?(current_user)
  end

  def team_admin_or_project_admin_required
    render_404 unless this_team.adminable_by?(current_user) || project_admin?
  end
end
