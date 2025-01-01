# typed: true
# frozen_string_literal: true

class MemexesController < AbstractRepositoryController
  include Memexes::ProjectListDependency


  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories

  preload_features [
    :tasklist_block,
    :otel_rack_middleware,
    :two_factor_checkup,
    :enterprise_banners_repo_level,
    :bus_ids_exclude_billing_manager_valid_license,
    :emu_vss_business,
    :proxima_avatar_tenant_slug_fix,
    :oidc_policy_enforced,
    :return_oidc_orgs_from_saml_enforcement_policy,
    :copilot_natural_language_github_search,
    :disable_notifications_automatic_watching_repositories,
    :disable_notifications_automatic_watching_teams,
  ]

  before_action :login_required
  before_action :require_memex_enabled

  before_action :set_client_uid
  before_action :set_cache_control_no_store

  javascript_bundle :"memex-index", only: [:index]

  layout "application"

  def index
    context_region_title "Projects"

    is_recent_selected = !params[:query]&.include?("creator:@me") && recently_visited_projects.any?

    # For pagination we just want to render the items and return these to the view
    if request&.xhr?
      return render Memex::ProjectList::ItemsContainerComponent.new(
        **list_projects(xhr: true).merge({
          is_recent_selected: !params[:query]&.present? && recently_visited_projects?
        })
      ), layout: false, locals: { page_title: "Projects" }
    end

    # the recent page is active, and we only need the subset of memexes that are recent
    if !params[:query]&.present?
      recently_visited = recently_visited_projects.to_a
      closed_count = recently_visited.count(&:closed?)
      return render "memexes/dashboard",
        locals: {
          project_owner: nil,
          memexes: recently_visited,
          has_next_page: false,
          cursor: nil,
          sort_query_cursor: nil,
          parsed_query: Search::Queries::MemexProjectQuery.new(params[:query]),
          open_memex_count: recently_visited.count - closed_count,
          closed_memex_count: closed_count,
          display_legacy_org_warning: false,
          is_recent_selected: true,
          show_templates_index: false,
          write_accessible_project_ids: MemexProject.async_filter_accessible_memexes(current_user, recently_visited, "write").sync.pluck(:id),
        }
    end

    list_projects_locals = list_projects(
      "index",
      recently_visited_projects: is_recent_selected ? recently_visited_projects : []
    )

    render "memexes/dashboard",
      locals: { **list_projects_locals.merge({
        display_legacy_org_warning: false,
        is_recent_selected: is_recent_selected,
      }) }
  end

  protected

  # shouldn't be necessary?
  def authorized?
    logged_in?
  end

  # Safe because :login_required
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  # Safe because :login_required
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  private

  memoize def recently_visited_projects
    return [] unless logged_in?

    # Perform the query and convert the relation to an array
    source.recently_visited_projects(viewer: current_user, cap_filter: cap_filter)
  end

  memoize def recently_visited_projects?
    recently_visited_projects.any?
  end

  # These are used on the "Created by me" tab, not "Recently viewed"

  memoize def source
    MemexProject::ProjectsDashboardContext.new(current_user)
  end

  # This would typically be a User or Organization, but for this dashboard we are rendering projects created by the
  # current_user across their personal projects or organizations they belong to. The underlying `MemexProject::ProjectsDashboardContext` implements the expected interface.
  def memex_owner
    source
  end

  def load_more_path
    projects_dashboard_path
  end

end
