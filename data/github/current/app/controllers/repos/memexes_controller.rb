# typed: true
# frozen_string_literal: true

# Repo-level memexes are actually a curation of org/user memexes. That means they represent a filtered view over the owner's (either org or user) memex projects
# The "curation" relationship is retained using the MemexProjectLinks model
# This controller is just fascilitating queries over the MemexProjectLinks model

class Repos::MemexesController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include ProjectsHelper
  include MemexesHelper
  include IssuesReactHelper
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
  before_action :require_verified_email_if_enabled, only: [:upsert_repo_project]
  before_action :set_pinned_views_sidebar_enabled, only: [:index]

  # The React row action menu calls `#unlink` and the React "Link a project" dialog
  # calls `#upsert_repo_project` via `verifiedFetchJSON`, which sends the
  # `GitHub-Verified-Fetch` header instead of an `authenticity_token`. Opt these
  # actions in to fetch verification so the requests aren't rejected as a CSRF
  # failure (422). The Rails kebab and Rails picker still post real forms with an
  # `authenticity_token`, and those paths remain protected by the default
  # forgery-protection strategy.
  allow_verified_fetch only: [:unlink, :upsert_repo_project]

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
    ApplicationRecord::Profiles,
    ApplicationRecord::Notify, only: [:index], optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:upsert_repo_project],
    optional: true

  javascript_bundle :"memex-index", only: [:index],
    unless: -> { T.bind(self, Repos::MemexesController); PinnedViewsFeature.projects_react_enabled?(current_repository, actor: current_user) }
  javascript_bundle :"issues-react", only: [:index],
    if: -> { T.bind(self, Repos::MemexesController); PinnedViewsFeature.projects_react_enabled?(current_repository, actor: current_user) }
  javascript_bundle :"repos-issues-sidebar", only: [:index],
    if: -> { T.bind(self, Repos::MemexesController); @pinned_views_sidebar_enabled }

  def index
    return render_404 if !current_repository.memex_projects_enabled?

    # The /projects/templates path is only meaningful for org-owned repos. Templates
    # are an organization-level feature; on a user-owned repo this URL has no
    # corresponding resource, so we 404 in either React-flag state.
    return render_404 if templates_path? && !memex_owner.is_a?(Organization)

    if PinnedViewsFeature.projects_react_enabled?(current_repository, actor: current_user)
      respond_to do |format|
        format.json { return render_projects_json }
        format.html { return issue_react_projects_handler }
      end
    end

    # The `/projects/templates` path is only meaningful when the React projects page is
    # enabled — the Rails view doesn't read the path. If the React flag is off but the
    # user lands on `/templates` (deep-link, bookmark, or stale cache), redirect to the
    # canonical Rails URL with the templates qualifier so they still see the right view.
    if templates_path?
      return redirect_to repo_projects_beta_path(query: "is:open is:template")
    end

    @sidebar_full_width_layout = @pinned_views_sidebar_enabled

    # For pagination we just want to render the items and return these to the view
    return render Memex::ProjectList::ItemsContainerComponent.new(
      **list_projects(xhr: true).merge({ is_recent_selected: false })
    ), layout: false, locals: { page_title: "Projects" } if request&.xhr?

    list_projects_locals = list_projects("index_repo")

    return redirect_to repo_projects_beta_path(params: {
        query: Search::Queries::MemexProjectQuery::DEFAULT_QUERY
      }), status: 307 if list_projects_locals.nil?

    render "memexes/repo_index", locals: { **list_projects_locals.merge({
      this_repository: current_repository,
      pinned_views_sidebar_enabled: @pinned_views_sidebar_enabled,
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

  def grant_role_on_create(memex) # rubocop:todo GitHub/UseRestfulActions
    memex.grant_role(current_user, :admin)
    true
  rescue Permissions::Granters::RoleGranter::GrantFailure
    memex.destroy!
    render(json: { errors: ["Error occured when creating project"] }, status: :unprocessable_entity)
    false
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

  # Whether the current request matches the `/:owner/:repo/projects/templates` route,
  # tolerating the optional `.<format>` suffix Rails accepts by default (e.g.
  # `/projects/templates.json`).
  def templates_path?
    request&.path&.match?(%r{/projects/templates(?:\.[^/]+)?\z})
  end

  def redirect_path # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @redirect_path ||= repo_projects_beta_path
  end

  def set_pinned_views_sidebar_enabled
    @pinned_views_sidebar_enabled = PinnedViewsFeature.enabled?(current_repository, actor: current_user)
  end

  def render_projects_json
    is_pagination_request = params[:cursor].present?
    event = is_pagination_request ? nil : "index_repo"
    list_projects_locals = list_projects(event)

    owner_is_organization = memex_owner.is_a?(Organization)
    viewer_is_org_member_or_manager = viewer_is_org_member_or_manager?

    onboarding_state = projects_onboarding_state

    if list_projects_locals.nil?
      return render json: {
        projects: [],
        openCount: 0,
        closedCount: 0,
        hasNextPage: false,
        cursor: nil,
        sortQueryCursor: nil,
        showTemplatesIndex: false,
        viewerCanPush: current_user_can_push?,
        viewerIsOrgMemberOrManager: viewer_is_org_member_or_manager,
        ownerIsOrganization: owner_is_organization,
        ownerLogin: memex_owner.display_login,
        newProjectAction: new_project_action,
        **onboarding_state,
      }
    end

    # `write_accessible_project_ids` is computed once per request in
    # `Memexes::ProjectListDependency#list_projects`. Convert to a Set so the per-row
    # lookup below stays O(1) regardless of page size.
    write_accessible_project_ids = Set.new(list_projects_locals[:write_accessible_project_ids] || [])

    viewer_present = current_user.present?

    projects = list_projects_locals[:memexes].map do |project|
      viewer_can_write = write_accessible_project_ids.include?(project.id)
      project_owner_is_organization = project.owner.is_a?(Organization)
      {
        id: project.id,
        number: project.number,
        title: project.title,
        shortDescription: project.short_description,
        closed: project.closed?,
        url: project.url.to_s,
        owner: project.owner.display_login,
        projectOwnerIsOrganization: project_owner_is_organization,
        updatedAt: project.updated_at&.iso8601,
        public: project.public?,
        viewerCanWrite: viewer_can_write,
        viewerCanCopy: viewer_present && (project.public? || viewer_can_write),
        viewerCanCopyAsTemplate: viewer_present &&
          project_owner_is_organization &&
          viewer_is_org_member_or_manager &&
          viewer_can_write,
      }
    end

    render json: {
      projects: projects,
      openCount: list_projects_locals[:open_memex_count],
      closedCount: list_projects_locals[:closed_memex_count],
      hasNextPage: list_projects_locals[:has_next_page],
      cursor: list_projects_locals[:cursor],
      sortQueryCursor: list_projects_locals[:sort_query_cursor],
      showTemplatesIndex: list_projects_locals[:show_templates_index],
      viewerCanPush: current_user_can_push?,
      # Page-level gate for menu items that require org membership (Copy as template).
      # Mirrors `Memex::ProjectList::ActionMenuComponent#viewer_is_org_member_or_manager?`.
      viewerIsOrgMemberOrManager: viewer_is_org_member_or_manager,
      ownerIsOrganization: owner_is_organization,
      ownerLogin: memex_owner.display_login,
      newProjectAction: new_project_action,
      **onboarding_state,
    }
  end

  def projects_onboarding_state
    user = current_user
    {
      dismissedNotices: {
        repoProjectsBetaSplash: user.present? && user.dismissed_notice?(Memex::ProjectsNewSplashComponent::REPO_PROJECT_SPLASH),
        repoProjectsBetaBanner: user.present? && user.dismissed_notice?(Memex::ProjectsNewBannerComponent::REPO_PROJECT_BANNER),
        projectsBetaSplash: user.present? && user.dismissed_notice?(Memex::ProjectsNewSplashComponent::PROJECT_SPLASH),
        projectsBetaBanner: user.present? && user.dismissed_notice?(Memex::ProjectsNewBannerComponent::PROJECT_BANNER),
      },
    }
  end

  # Hidden-field bundle for the React "New project" form, mirroring
  # `Memex::ProjectList::AddOrLinkProjectButtonContainerComponent` on the Rails view.
  # Returns nil for viewers who can't create the project, so the React side hides the
  # CTA entirely instead of presenting one that 404s on submit.
  #
  # Gated on the same check the upsert path's create branch enforces
  # (`viewer_is_org_member_or_owner?` on top of push access). Outside collaborators with
  # write access can push but can't create projects on this repo, so they don't get the
  # CTA either.
  #
  # Returned alongside the projects list rather than via `add_csrf_token` / the route
  # payload because `RepositoryProjectsPage` is a relayRoute, whose route state
  # doesn't expose the html payload to React hooks like `useCSRFToken`.
  def new_project_action
    user = current_user
    return nil if user.nil? || !current_user_can_push? || !viewer_is_org_member_or_owner?

    {
      csrfToken: authenticity_token_for(upsert_repo_project_beta_path(memex_owner, current_repository), method: :put),
      defaultTitle: MemexProject.default_user_title(user),
    }
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

  def require_verified_email_if_enabled
    return unless FeatureFlag.vexi.enabled?(:require_verified_email_check_for_enterprise, current_user, default: false)

    require_verified_email
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

  def viewer_is_org_member_or_owner?
    if memex_owner.organization?
      memex_owner.direct_or_team_member?(current_user)
    else
      memex_owner == current_user
    end
  end

  # Whether the viewer is a member or billing manager of any organization. Mirrors
  # `Memex::ProjectList::ActionMenuComponent#viewer_is_org_member_or_manager?`, which
  # gates the "Copy as template" menu item on the Rails view. Surfaced in the React
  # JSON payload so the React menu can apply the same gate without a follow-up
  # request.
  def viewer_is_org_member_or_manager?
    user = current_user
    return false if user.nil?

    user.member_or_billing_manager_for_any_organization?
  end
end
