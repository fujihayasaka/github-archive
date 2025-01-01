# typed: false
# frozen_string_literal: true

module Profiles
  class ProjectsController < ApplicationController
    include ProfilesHelper
    include ProjectsHelper
    include ProjectControllerActions
    include UserContributionsHelper

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    DEFAULT_PAGE_SIZE = 30

    set_statsd_sample_rate 0.01, only: :index

    around_action :record_profile_stats, only: :index
    skip_before_action :cap_pagination, only: :index

    before_action :require_user, only: :index
    before_action :require_user_projects_enabled
    before_action :ensure_profile_visible

    javascript_bundle :profile
    stylesheet_bundle :profile
    stylesheet_bundle :projects

    javascript_bundle :"memex-index", only: [:index]


    ProjectsIndexQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
      query($projectOwnerId: ID!, $first: Int!, $after: String, $query: String) {
        node(id: $projectOwnerId) {
          ...Views::Users::Tabs::Projects::User
        }
      }
    GRAPHQL

    UserShowQuery = parse_query <<-'GRAPHQL' # rubocop:todo GitHub/DoNotCallParseQuery
      query(
        $id: ID!,
        $query: String,
        $first: Int,
        $after: String,
      ) {
        node(id: $id) {
          ...Views::Users::Tabs::Projects::User
        }
      }
    GRAPHQL

    def index
      # We're shortcircuiting this for mannequins as it is causing 500s down the line
      return render_404 if this_user.mannequin?

      respond_to do |format|
        format.html do
          instrument_hydro_user_profile_page_view

          render_user_profile
        end
      end
    end

    private

    def search_query(add_sort_option = true)
      return @search_query if defined? @search_query
      @search_query = project_index_query(add_sort_option)
    end

    def render_user_profile
      if request.xhr? && !pjax?
        render_user_projects_tab
      elsif query_contains_beta?
        redirect_to user_path(this_user, params: { tab: "projects" }.merge(redirect_params)), status: 307
      elsif query_contains_classic?
        render_projects
      elsif !GitHub.projects_new_enabled?
        redirect_to user_path(this_user, params: { tab: "projects", type: "classic" }.merge(redirect_params)), status: 307
      else
        render_memex_projects
      end
    end

    def render_projects
      return render_404 if disable_classic_projects(this_user)

      variables = {
        id: this_user.global_relay_id,
        query: search_query,
      }
      variables.merge!(graphql_pagination_params(page_size: DEFAULT_PAGE_SIZE))
      data = platform_execute(UserShowQuery, variables: variables, context: { enforce_conditional_access_via_graphql: true })
      if user = data.node
        render "users/tabs/projects/index", locals: {
          user: user,
          data: {
            open_memex_count: projects_beta_count,
            query_contains_beta: false,
            disable_classic_project_creation: disable_classic_projects_creation_for_user?(this_user, current_user)
          },
          disable_classic_projects: disable_classic_projects(this_user),
          layout_data: Profiles::User::LayoutData.preload(
            profile_user: this_user,
            viewer: current_user,
            active_tab: :projects,
          ),
        }
      else
        render_404
      end
    end

    def render_memex_projects
      return render_404 unless GitHub.projects_new_enabled?

      query = Search::Queries::MemexProjectQuery.new(search_query(false))

      search_result = this_user.search_memex_projects(
        query: query,
        viewer: current_user,
        cursor: params[:cursor],
        sort_query_cursor: params[:sort_query_cursor],
        limit: DEFAULT_PAGE_SIZE,
      )

      instrument_hydro_memex_index_search if params[:q]

      memex_projects = search_result.memex_projects
      is_viewer = current_user == this_user
      write_accessible_project_ids = if is_viewer
        memex_projects.pluck(:id)
      else
        MemexProject.async_filter_accessible_memexes(current_user, memex_projects, "write").sync.pluck(:id)
      end

      render "users/tabs/projects/index", locals: {
        user: this_user,
        data: {
          is_viewer: is_viewer,
          memex_projects: memex_projects,
          memex_query: query,
          has_next_page: search_result.has_next_page?,
          cursor: search_result.next_page_cursor,
          sort_query_cursor: search_result.sort_query_cursor,
          open_memex_count: search_result.total_open_count,
          closed_memex_count: search_result.total_closed_count,
          projects_count: open_projects_count(this_user),
          query_contains_beta: true,
          disable_classic_project_creation: disable_classic_projects_creation_for_user?(this_user, current_user),
          write_accessible_project_ids: write_accessible_project_ids,
        },
        disable_classic_projects: disable_classic_projects(this_user),
        layout_data: Profiles::User::LayoutData.preload(
          profile_user: this_user,
          viewer: current_user,
          active_tab: :projects,
        )
      }
    end

    def render_user_projects_tab
      params[:query] ||= "is:open"

      variables = {
        projectOwnerId: this_user.global_relay_id,
        first: DEFAULT_PAGE_SIZE,
        after: params[:cursor],
        query: project_index_query,
      }
      variables.merge!(graphql_pagination_params(page_size: DEFAULT_PAGE_SIZE))
      result = platform_execute(ProjectsIndexQuery, variables: variables)
      render partial: "users/tabs/projects", locals: {
        query: params[:query],
        user: result.node,
        data: {
          open_memex_count: projects_beta_count
        },
        disable_classic_projects: disable_classic_projects(this_user),
        user_session: user_session,
      }
    end

    def instrument_hydro_user_profile_page_view
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: :UNKNOWN, # maintains feature parity
      )
    end

    def instrument_hydro_memex_index_search
      GlobalInstrumenter.instrument("memex_event",
        {
          actor: current_user,
          memex_project: nil,
          memex_project_column: nil,
          memex_project_item: nil,
          name: "index_search",
          ui: "user_index",
          context: params[:q],
          memex_project_view: nil,
        }
      )
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def require_user
      if this_user.nil?
        render_404
      elsif this_user.organization?
        redirect_to user_path(this_user)
      end
    end

    def record_profile_stats
      return yield unless logged_in? && this_user && !this_user.organization?

      before = Time.now
      yield
      duration = Time.now - before

      tags = ProfilesController::ShowProfileStats.tags(
        activity_overview_rendered: activity_overview_enabled?,
        subject_user: this_user,
        viewer: current_user,
      )

      GitHub.dogstats.distribution("user.profile.projects.request", duration * 1000, tags: tags)
    end

    memoize def projects_beta_count
      return 0 unless GitHub.projects_new_enabled?
      this_user.accessible_memexes_scope(
        this_user.memex_projects.open_projects,
        current_user,
      ).count
    end

    def show_memex_ui_for_current_user
      return false unless GitHub.projects_new_enabled?
      return true if this_user == current_user

      projects_beta_count > 0
    end

    def query_contains_beta?
      params[:type] == "beta" || params[:type] == "new"
    end

    def query_contains_classic?
      params[:type] == "classic"
    end

    def redirect_params
      params.has_key?(:query) ? { query: params[:query] } : {}
    end

    helper_method :show_memex_ui_for_current_user
    # These helper methods come from ProjectControllerActions
    helper_method :parsed_projects_query
    helper_method :project_index_query
  end
end
