# typed: true
# frozen_string_literal: true

# Repo-level memexes are actually a curation of org/user memexes. That means they represent a filtered view over the owner's (either org or user) memex projects
# The "curation" relationship is retained using the MemexProjectLinks model
# This controller is just fascilitating queries over the MemexProjectLinks model

class Repos::MemexesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ProjectsHelper
  include MemexesHelper
  include Memexes::ProjectLinkDependency
  include Memexes::ProjectListDependency
  include Memexes::GrantRoleOnCreateDependency
  include Memexes::SharedMemexesControllerActions

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Repos::MemexesController#unlink",
    "Repos::MemexesController#upsert_repo_project"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex

  before_action :login_required, only: [:unlink, :upsert_repo_project]
  before_action :require_memex_project_id, only: [:unlink]
  before_action :require_memex_feature_enabled
  before_action :require_repo_projects_enabled
  before_action :write_access_required, only: [:unlink, :upsert_repo_project]

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests, only: [:index]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Billing,
    ApplicationRecord::Notify, only: [:index], optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:upsert_repo_project],
    optional: true

  javascript_bundle :"memex-index", only: [:index]

  def index
    return render_404 if !current_repository.memex_projects_enabled?

    # For pagination we just want to render the items and return these to the view
    return render Memex::ProjectList::ItemsContainerComponent.new(
      **list_projects(xhr: true).merge({ is_recent_selected: false })
    ), layout: false, locals: { page_title: "Projects" } if request&.xhr?

    list_projects_locals = list_projects("index_repo")

    return redirect_to repo_projects_beta_path(params: {
        query: Search::Queries::MemexProjectQuery::DEFAULT_QUERY
      }), status: 307 if list_projects_locals.nil?

    render "memexes/repo_index", locals: { **list_projects_locals.merge({
      this_repository: current_repository
    }) }
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab, only: [:unlink]
  depends_on_clusters ApplicationRecord::Spokes,
    ApplicationRecord::Ballast, only: [:unlink], optional: true

  def unlink # rubocop:todo GitHub/UseRestfulActions
    unlink_project(
      context: current_repository,
      redirect_path: redirect_path,
      publish_remove_event: method(:publish_repo_link_remove)
    )
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab, only: [:upsert_repo_project]
  depends_on_clusters ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify, only: [:upsert_repo_project], optional: true

  def upsert_repo_project # rubocop:todo GitHub/UseRestfulActions
    if params[:action_type] == "create"
      return render_404 unless viewer_is_org_member_or_owner?
      create do |memex|
        # Upon Memex being created, establish the link between the newly created MemexProject and repository
        MemexProjectLink.new(source: current_repository, memex_project: memex).save

        publish_repo_create_project(memex: memex)
      end
    elsif params[:action_type] == "link"
      update_links
    else
      redirect_back_or_to redirect_path
    end
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests, only: [:projects_suggestions]
  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Notify, only: [:projects_suggestions], optional: true

  def projects_suggestions # rubocop:todo GitHub/UseRestfulActions
    only_memex_templates = params[:filter] == "templates"
    scope = params[:scope].presence || (params.include?(:q) && params[:q].blank? ? "recent" : nil)

    suggestions = project_suggestions(
      scope,
      current_repository,
      only_memex_templates: only_memex_templates,
      q: params[:q],
      limit: 200
    )

    respond_to do |format|
      format.json { render(json: suggestions) }
      format.any(:html, :html_fragment) do
        render(
          "repos/memexes/projects_suggestions",
          layout: false,
          locals: { suggestions: suggestions },
          formats: [:html, :html_fragment]
        )
      end
    end
  end

  private

  def source
    current_repository
  end

  def load_more_path
    repo_projects_beta_path
  end

  def memex_owner
    current_repository.owner
  end

  def redirect_path # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @redirect_path ||= repo_projects_beta_path
  end

  def write_access_required
    head :forbidden unless current_user_can_push?
  end

  def require_memex_feature_enabled
    render_404 unless GitHub.projects_new_enabled?
  end

  def require_repo_projects_enabled
    render_404 unless current_repository.repository_projects_enabled? || current_repository.repository_memex_projects_enabled?
  end

  def require_memex_project_id
    head :bad_request unless params[:memex_project_id]
  end

  def should_skip_memex_index_hydro
    flash[:skip_memexes_controller_index_hydro] == "true"
  end

  def publish_repo_link_add(memex:)
    publish_repo_memex_event(name: "repo_link_add", memex: memex)
  end

  def publish_repo_link_remove(memex:)
    publish_repo_memex_event(name: "repo_link_remove", memex: memex)
  end

  def publish_repo_create_project(memex:)
    publish_repo_memex_event(name: "repo_create_project", memex: memex)
  end

  def publish_repo_memex_event(name:, memex: nil)
    GlobalInstrumenter.instrument("memex_event",
      {
        actor: current_user,
        memex_project: memex,
        memex_project_column: nil,
        memex_project_item: nil,
        name: name,
        ui: nil,
        context: "",
        memex_project_view: nil,
        repository: current_repository,
      }
    )
  end

  def update_links
    update_project_links(
      update_links_params: update_links_params,
      context: current_repository,
      redirect_path: redirect_path,
      publish_add_event: method(:publish_repo_link_add),
      publish_remove_event: method(:publish_repo_link_remove)
    )
  end

  def update_links_params
    params.to_unsafe_h.with_indifferent_access[:projects_changes]
  end

  def grant_role_on_create(memex)
    memex.grant_role(current_user, :admin)
    true
  rescue Permissions::Granters::RoleGranter::GrantFailure
    memex.destroy!
    render(json: { errors: ["Error occured when creating project"] }, status: :unprocessable_entity)
    false
  end

  def viewer_is_org_member_or_owner?
    if memex_owner.organization?
      memex_owner.direct_or_team_member?(current_user)
    else
      memex_owner == current_user
    end
  end

end
