# typed: true
# frozen_string_literal: true

class Orgs::ProjectsController < Orgs::Controller
  include ProjectControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :render_404_unless_projects_classic_ui_enabled_for_current_user, except: %w[show]
  before_action :require_projects_enabled
  before_action :this_project_required, except: %w[index destroy linkable_repositories]
  before_action :project_read_required, except: %w[index destroy linkable_repositories]
  before_action :project_write_required, except: %w[index show clone destroy activity target_owner_results linkable_repositories]
  before_action :current_user_required, only: [:clone, :target_owner_results]
  before_action :set_client_uid
  before_action :set_cache_control_no_store, only: [:show, :search_results]

  stylesheet_bundle :projects

  layout "org_projects"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:search_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:target_owner_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:repository_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:activity]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:add_cards_link]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:linkable_repositories]

  depends_on_clusters ApplicationRecord::Copilot, only: [
    :activity,
    :add_cards_link,
    :edit,
    :index,
    :repository_results,
    :search_results,
    :target_owner_results,
    :show
  ], optional: true

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

  def index
    # if Org is within Enterprise Managed User enabled business
    # it is NOT viewable by non Enterprise-Managed users (including anonymous
    # requests)
    if this_organization.enterprise_managed_user_enabled?
      return render_404 unless current_user&.enterprise_managed_business == this_organization.business
    end

    render_404
  end

  def edit
    override_analytics_location "/orgs/<org-login>/projects/<id>/edit"
    render_edit_project(owner: this_organization, project: this_project)
  end

  def show
    override_analytics_location "/orgs/<org-login>/projects/<id>"
    strip_analytics_query_string

    render_show_project(
      owner: this_organization,
      project: this_project,
      migration_notice_partial_path: org_project_migration_status_notice_partial_path
    )
  end

  def search_results # rubocop:todo GitHub/UseRestfulActions
    render_project_search_results(owner: this_organization, project: this_project)
  end

  def activity # rubocop:todo GitHub/UseRestfulActions
    render_project_activity(owner: this_organization, project: this_project)
  end

  def add_cards_link # rubocop:todo GitHub/UseRestfulActions
    render_project_add_cards_link(project: this_project)
  end

  def update
    update_project(owner: this_organization, project: this_project)
  end

  def update_state # rubocop:todo GitHub/UseRestfulActions
    update_project_state(project: this_project, state: params[:state], sync: params[:sync])
  end

  def clone # rubocop:todo GitHub/UseRestfulActions
    clone_project(project: this_project)
  end

  def migrate # rubocop:todo GitHub/UseRestfulActions
    migrate_project(project: this_project, close_source_project: params[:close_source_project])
  end

  def dismiss_notice # rubocop:todo GitHub/UseRestfulActions
    dismiss_project_notice(project: this_project, project_owner: this_organization, notice: params[:notice])
  end

  def destroy
    destroy_project(owner: this_organization)
  end

  def repository_results # rubocop:todo GitHub/UseRestfulActions
    if params[:search_in] == "suggestions"
      repos = this_project.repository_suggestions(viewer: current_user, filter: params[:q])
    else
      query = Search::Queries::RepoQuery.new \
          current_user: current_user,
          user_session: user_session,
          remote_ip:    request.remote_ip,
          cap_filter:   cap_filter,
          phrase:       "org:#{this_organization.login} #{params[:q]}" # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194

      repos = query.execute.results.map { |result| result["_model"] }
      repos.select! { |repo| repo.has_issues? }
    end
    respond_to do |format|
      format.html_fragment { render partial: "projects/repository_results", formats: :html, locals: { repositories: repos } }
    end
  end

  def target_owner_results # rubocop:todo GitHub/UseRestfulActions
    render_target_owner_results(project: this_project)
  end

  def linkable_repositories # rubocop:todo GitHub/UseRestfulActions
    render_linkable_repositories(owner: this_organization, project: this_project)
  end

  def migration_status_notice_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Memex::ProjectDeprecationNoticeComponent.new(
          project: this_project,
          data_url: org_project_migration_status_notice_partial_path,
        ), layout: false
      end
    end
  end

  private

  helper_method :parsed_projects_query

  memoize def this_project
    # We don't load through visible_projects_for here, since permissions are
    # checked in before_actions.
    return unless this_organization
    if params[:action] == "new"
      this_organization.projects.build
    elsif params[:action] == "create"
      this_organization.projects.new(name: project_params[:name], body: project_params[:body])
    else
      this_organization.projects.find_by(number: params[:number])
    end
  end

  def this_project_required
    render_404 if this_project.nil?
  end

  def project_read_required
    render_404 unless this_project.readable_by?(current_user)
  end

  def current_user_required
    render_404 unless logged_in?
  end

  def project_write_required
    return true if this_project.writable_by?(current_user)
    return render_404 unless this_project.readable_by?(current_user)

    # If we can read the project but can't write it, show an informative error
    # message or status code.
    respond_to do |format|
      format.html do
        flash[:error] = "You don't have permission to perform this action on this project."
        redirect_to project_path(this_project)
      end

      format.json do
        head 403
      end
    end
  end

  def resource_for_conditional_access
    # return the controller itself for actions which are not required to have a project and there is no project
    # so that it can return the potential owner of the project.
    return self if %w(index create new destroy linkable_repositories).include?(action_name)
    return self unless this_project
    this_project
  end
end
