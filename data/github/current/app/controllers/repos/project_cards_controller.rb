# typed: false
# frozen_string_literal: true

class Repos::ProjectCardsController < AbstractRepositoryController
  include ProjectCardControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :require_projects_classic_ui_enabled_for_current_user
  before_action :require_push_access, except: [:archived, :check_archived, :index, :pull_request_status, :search_archived, :show, :closing_references]
  before_action :set_client_uid
  before_action :require_projects_enabled
  before_action :set_cache_control_no_store, only: [:index]

  rescue_from ProjectColumn::LegacySortingOverridesDependency::PrioritizingArchivedCardError, ProjectColumn::LegacySortingOverridesDependency::InvalidPrioritizationTargetError do |error|
    render_422(error)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:closing_references]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:preview_note]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:card_columns]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:check_archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:closing_reference]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:pull_request_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:search_archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :archived,
      :search_archived,
      :pull_request_status,
      :preview_note,
      :closing_references,
      :closing_reference,
      :check_archived,
      :card_columns,
      :show,
      :index,
    ], optional: true

  def index
    render_project_cards_index(project: this_project)
  end

  def archived # rubocop:todo GitHub/UseRestfulActions
    render_archived_project_cards(project: this_project)
  end

  def search_archived # rubocop:todo GitHub/UseRestfulActions
    render_search_archived_project_cards(project: this_project)
  end

  def check_archived # rubocop:todo GitHub/UseRestfulActions
    render_check_archived_project_card(project: this_project)
  end

  def show
    render_show_project_card(project: this_project)
  end

  def update
    update_project_card(project: this_project, repository: current_repository)
  end

  def update_note # rubocop:todo GitHub/UseRestfulActions
    update_project_card_note(project: this_project)
  end

  def update_note_task_list # rubocop:todo GitHub/UseRestfulActions
    update_project_card_note_task_list(project: this_project)
  end

  def convert_to_issue # rubocop:todo GitHub/UseRestfulActions
    convert_project_card_to_issue(project: this_project, repository: current_repository)
  end

  def preview_note # rubocop:todo GitHub/UseRestfulActions
    preview_project_note(project: this_project, repository: current_repository)
  end

  def pull_request_status # rubocop:todo GitHub/UseRestfulActions
    render_pull_request_status(project: this_project)
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    archive_project_card(project: this_project)
  end

  def unarchive # rubocop:todo GitHub/UseRestfulActions
    unarchive_project_card(project: this_project)
  end

  def closing_references # rubocop:todo GitHub/UseRestfulActions
    render_project_card_closing_references(project: this_project)
  end

  def closing_reference # rubocop:todo GitHub/UseRestfulActions
    render_project_card_closing_reference(project: this_project)
  end

  def destroy
    destroy_project_card(project: this_project)
  end

  private

  memoize def this_project
    current_repository.projects.find_by_number!(params[:project_number])
  end

  def require_push_access
    render_404 unless current_user_can_push?
  end
end
