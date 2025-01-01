# typed: true
# frozen_string_literal: true

class Repos::ProjectsController < AbstractRepositoryController
  include ProjectControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :require_projects_classic_ui_enabled_for_current_user
  before_action :require_push_access, except: [:index, :show, :clone, :destroy, :activity, :target_owner_results]
  before_action :user_with_project_read_required, only: [:clone, :target_owner_results]
  before_action :set_client_uid
  before_action :require_projects_enabled
  before_action :require_projects_create_enabled, only: [:new, :create]
  before_action :non_migrating_repository_required, except: [:index, :show]
  before_action :set_cache_control_no_store, only: [:show, :search_results]

  stylesheet_bundle :projects

  layout "repository"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    only: [:activity]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    only: [:add_cards_link]

  depends_on_clusters ApplicationRecord::IssuesPullRequests, only: [:activity, :add_cards_link], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Spokes,
    only: [:search_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:target_owner_results]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :activity, :add_cards_link, :new, :search_results, :target_owner_results],
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

  def index
    render_projects_index(owner: current_repository)
  end

  def new
    render_new_project(owner: current_repository)
  end

  def edit
    render_edit_project(owner: current_repository, project: this_project)
  end

  def show
    render_show_project(
      owner: current_repository,
      project: this_project,
      migration_notice_partial_path: repo_project_migration_status_notice_partial_path
    )
  end

  def create
    create_project(owner: current_repository)
  end

  def update
    update_project(owner: current_repository, project: this_project)
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
    dismiss_project_notice(project: this_project, project_owner: current_repository, notice: params[:notice])
  end

  def search_results # rubocop:todo GitHub/UseRestfulActions
    render_project_search_results(owner: current_repository, project: this_project)
  end

  def activity # rubocop:todo GitHub/UseRestfulActions
    render_project_activity(owner: current_repository, project: this_project)
  end

  def add_cards_link # rubocop:todo GitHub/UseRestfulActions
    render_project_add_cards_link(project: this_project)
  end

  def destroy
    destroy_project(owner: current_repository)
  end

  def target_owner_results # rubocop:todo GitHub/UseRestfulActions
    render_target_owner_results(project: this_project)
  end

  def migration_status_notice_partial # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Memex::ProjectDeprecationNoticeComponent.new(
          project: this_project,
          data_url: repo_project_migration_status_notice_partial_path,
        ), layout: false
      end
    end
  end

  private

  def resource_for_conditional_access
    # return the controller itself for actions which are not required to have a project
    # so that it can return the potential owner of the project.
    return self if %w(index create new destroy).include?(action_name)
    return :no_resource_for_conditional_access unless this_project # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    this_project
  end

  helper_method :parsed_projects_query

  def require_push_access
    return true if current_user_can_push?
    return render_404 unless this_project.readable_by?(current_user)
    return render_404 unless this_project.persisted?

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

  def user_with_project_read_required
    render_404 unless logged_in? && this_project.readable_by?(current_user)
  end

  def require_projects_create_enabled
    render_404 if disable_classic_projects_creation_for_user?(current_repository, current_user)
  end

  memoize def this_project
    if params[:action] == "new"
      current_repository.projects.build
    elsif params[:action] == "create"
      current_repository.projects.new(name: project_params[:name], body: project_params[:body])
    else
      current_repository.projects.find_by_number!(params[:number])
    end
  end

  memoize def this_organization
    if current_repository
      owner = current_repository.owner
      owner&.organization? ? owner : nil
    end
  end
end
