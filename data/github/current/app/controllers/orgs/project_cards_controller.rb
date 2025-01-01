# typed: false
# frozen_string_literal: true

class Orgs::ProjectCardsController < Orgs::Controller
  include ProjectCardControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :render_404_unless_projects_classic_ui_enabled_for_current_user
  before_action :project_read_required
  before_action :require_projects_enabled
  before_action :project_write_required, except: [:archived, :check_archived, :index, :pull_request_status, :search_archived, :show, :closing_references]
  before_action :set_client_uid
  before_action :set_cache_control_no_store, only: [:index]

  rescue_from ProjectColumn::LegacySortingOverridesDependency::PrioritizingArchivedCardError, ProjectColumn::LegacySortingOverridesDependency::InvalidPrioritizationTargetError do |error|
    render_422(error)
  end

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
    only: [:archived]

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
    only: [:card_columns]

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
    only: [:check_archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:closing_reference]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:closing_references]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:preview_note]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:pull_request_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    only: [:search_archived]

  depends_on_clusters ApplicationRecord::Copilot, only: [
    :archived,
    :card_columns,
    :check_archived,
    :closing_reference,
    :closing_references,
    :search_archived,
    :show,
    :pull_request_status,
    :preview_note,
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
    update_project_card(project: this_project)
  end

  def update_note # rubocop:todo GitHub/UseRestfulActions
    update_project_card_note(project: this_project)
  end

  def update_note_task_list # rubocop:todo GitHub/UseRestfulActions
    update_project_card_note_task_list(project: this_project)
  end

  def convert_to_issue # rubocop:todo GitHub/UseRestfulActions
    repository_id = params[:repository_id]&.to_i

    associated_repo_ids = current_user.associated_repository_ids(
      including: [:direct, :indirect],
      repository_ids: [repository_id],
    )

    repository = Repository.owned_by(this_organization).where(id: associated_repo_ids).find(repository_id)

    convert_project_card_to_issue(project: this_project, repository: repository)
  end

  def preview_note # rubocop:todo GitHub/UseRestfulActions
    preview_project_note(project: this_project)
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
    this_organization.visible_projects_for(current_user).find_by_number!(params[:project_number])
  end

  def project_read_required
    render_404 unless this_project.readable_by?(current_user)
  end

  def project_write_required
    render_404 unless this_project.writable_by?(current_user)
  end
end
