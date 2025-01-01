# typed: true
# frozen_string_literal: true

class Users::ProjectsController < Users::Controller
  include ProjectControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  layout "layouts/user_projects"

  before_action :render_404_unless_projects_classic_ui_enabled_for_current_user, except: %w[show]
  before_action :current_user_required, except: %w[index show]
  before_action :require_user_projects_enabled
  before_action :require_this_user, except: [:new]
  before_action :this_project_required, except: %w[index new create destroy linkable_repositories]
  before_action :project_read_required, except: %w[index new create destroy linkable_repositories]
  before_action :project_write_required, except: %w[index new create show activity target_owner_results destroy linkable_repositories clone]
  before_action :require_projects_create_enabled, only: [:new, :create]
  before_action :set_client_uid
  before_action :set_cache_control_no_store, only: %w[show search_results]

  stylesheet_bundle :projects

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:target_owner_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:activity]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:add_cards_link]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:linkable_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:repository_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:search_results]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :new, :edit, :search_results, :activity, :add_cards_link],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    only: [:migration_status_notice_partial]

  depends_on_clusters ApplicationRecord::Repositories,
    only: [:show]

  def index
    if referring_params[:controller] == "repos/memexes" && referring_params[:action] == "index"
      GlobalInstrumenter.instrument("memex_event",
        {
          actor: current_user,
          memex_project: nil,
          memex_project_column: nil,
          memex_project_item: nil,
          name: "index",
          ui: nil,
          context: params[:query],
          memex_project_view: nil,
          repository: this_user.repositories.find_by_name(referring_params[:repository]),
        }
      )
    end

    if request.xhr? && !pjax?
      if params[:type] == "classic"
        render_projects_index(owner: this_user)
      else
        render_memexes_index(owner: this_user)
      end
    else
      # We need to do this manually because our overridden user_path helper
      # doesn't allow keyword args.
      args = "?tab=projects"
      args += "&q=#{params[:query]}" if params[:query].present?
      args += "&type=#{params[:type]}" if params[:type].present? && params[:type] == "classic"

      redirect_to user_path(this_user) + args, status: 307
    end
  end

  def new
    render_new_project(owner: current_user)
  end

  def edit
    override_analytics_location "/users/<user-login>/projects/<id>/edit"
    render_edit_project(owner: this_user, project: this_project)
  end

  def show
    override_analytics_location "/users/<user-login>/projects/<id>"
    strip_analytics_query_string

    render_show_project(
      owner: this_user,
      project: this_project,
      migration_notice_partial_path: user_project_migration_status_notice_partial_path
    )
  end

  def search_results # rubocop:todo GitHub/UseRestfulActions
    render_project_search_results(owner: this_user, project: this_project)
  end

  def activity # rubocop:todo GitHub/UseRestfulActions
    render_project_activity(owner: this_user, project: this_project)
  end

  def add_cards_link # rubocop:todo GitHub/UseRestfulActions
    render_project_add_cards_link(project: this_project)
  end

  def create
    return render_404 if this_user != current_user

    create_project(owner: this_user)
  end

  def update
    update_project(owner: this_user, project: this_project)
  end

  def update_state # rubocop:todo GitHub/UseRestfulActions
    update_project_state(project: this_project, state: params[:state], sync: params[:sync])
  end

  def clone # rubocop:todo GitHub/UseRestfulActions
    clone_project(project: this_project)
  end

  def destroy
    destroy_project(owner: this_user)
  end

  def repository_results # rubocop:todo GitHub/UseRestfulActions
    if params[:search_in] == "suggestions"
      repos = this_project.repository_suggestions(viewer: current_user, filter: params[:q])
    else
      query = Search::Queries::RepoQuery.new(
        current_user: current_user,
        remote_ip: request.remote_ip,
        cap_filter: cap_filter,
        phrase: "user:#{this_user.display_login} #{params[:query]}",
      )

      repos = query.execute.results.map { |result| result["_model"] }.select(&:has_issues?)
    end

    respond_to do |format|
      format.html_fragment do
        render partial: "projects/repository_results", formats: :html, locals: { repositories: repos }
      end
    end
  end

  def target_owner_results # rubocop:todo GitHub/UseRestfulActions
    render_target_owner_results(project: this_project)
  end

  def linkable_repositories # rubocop:todo GitHub/UseRestfulActions
    render_linkable_repositories(owner: this_user, project: this_project)
  end

  def migrate # rubocop:todo GitHub/UseRestfulActions
    migrate_project(project: this_project, close_source_project: params[:close_source_project])
  end

  def dismiss_notice # rubocop:todo GitHub/UseRestfulActions
    dismiss_project_notice(project: this_project, project_owner: this_user, notice: params[:notice])
  end

  def migration_status_notice_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Memex::ProjectDeprecationNoticeComponent.new(
          project: this_project,
          data_url: user_project_migration_status_notice_partial_path,
        ), layout: false
      end
    end
  end

  protected

  def resource_for_conditional_access
    # return the controller itself for actions which are not required to have a project
    # so that it can return the potential owner of the project.
    return self if %w(index new create destroy linkable_repositories).include?(action_name)
    return :no_resource_for_conditional_access unless this_user && this_project # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    this_project
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return this_project.target_for_conditional_access if this_project&.persisted?
    this_user
  end

  private

  def render_memexes_index(owner:)
    parsed_query = Search::Queries::MemexProjectQuery.new(params[:query])

    search_result = owner.search_memex_projects(
      query: parsed_query,
      viewer: current_user,
      cursor: params[:cursor],
      sort_query_cursor: params[:sort_query_cursor],
      limit: PAGE_SIZE,
    )

    render partial: "memexes/list", locals: {
      project_owner: owner,
      memexes: search_result.memex_projects,
      has_next_page: search_result.has_next_page?,
      cursor: search_result.next_page_cursor,
      sort_query_cursor: search_result.sort_query_cursor,
      parsed_query: parsed_query,
      is_recent_selected: false,
      viewer_is_a_member: current_user == owner,
      has_any_memex_projects: owner.memex_projects.any?
    }
  end

  memoize def this_project
    if params[:action] == "new"
      return unless logged_in?
      current_user.projects.build
    elsif params[:action] == "create"
      return unless logged_in?
      current_user.projects.new(name: project_params[:name], body: project_params[:body])
    else
      # Finding a project by number is more expensive than it should be for a user
      # with a large number of projects, but most such users are spammy.
      #
      # Instead of performing the expensive query, hide the project from the spammy
      # user. See https://github.com/github/fanout/issues/417.
      if GitHub.flipper[:hide_classic_projects_for_spammy_users].enabled? && this_user.spammy?
        return nil
      end

      this_user.projects.find_by(number: params[:number])
    end
  end
  helper_method :this_project

  def require_projects_create_enabled
    # this_user is not required on /new, but we can use the current user as project owner
    render_404 if disable_classic_projects_creation_for_user?(current_user, current_user)
  end

  def this_project_required
    render_404 if this_project.nil?
  end

  def project_read_required
    render_404 unless this_project.readable_by?(current_user)
  end

  def project_write_required
    return true if this_project.writable_by?(current_user)
    return render_404 unless this_project.readable_by?(current_user)

    # If we can read the project but can't write it, show an informative error
    # message or status code.
    respond_to do |format|
      format.html_fragment do
        head 403
      end

      format.json do
        head 403
      end

      format.html do
        flash[:error] = "You don't have permission to perform this action on this project."
        redirect_to project_path(this_project)
      end
    end
  end

  def current_user_required
    render_404 unless logged_in?
  end

  helper_method :parsed_projects_query
  helper_method :project_index_query
end
