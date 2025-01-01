# typed: false
# frozen_string_literal: true

class Users::ProjectCardsController < Users::Controller
  include ProjectCardControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :require_projects_classic_ui_enabled_for_current_user
  before_action :hide_spammy_projects
  before_action :this_project_required
  before_action :project_read_required
  before_action :project_write_required, except: [:archived, :check_archived, :index, :pull_request_status, :search_archived, :show, :closing_references]
  before_action :set_client_uid
  before_action :set_cache_control_no_store, only: [:index]

  rescue_from ProjectColumn::LegacySortingOverridesDependency::PrioritizingArchivedCardError, ProjectColumn::LegacySortingOverridesDependency::InvalidPrioritizationTargetError do |error|
    render_422(error)
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:card_columns]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:check_archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:closing_reference]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:closing_references]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    only: [:preview_note]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:pull_request_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    only: [:search_archived]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :check_archived, :closing_reference, :closing_references, :pull_request_status,
      :card_columns, :preview_note, :archived, :search_archived],
    optional: true

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
    associated_repo_ids = current_user.associated_repository_ids(repository_ids: [repository_id])
    repository = Repository.owned_by(this_user).where(id: associated_repo_ids).find(repository_id)

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

  protected

  def target_for_conditional_access
    # While CAP bypass works here (because of project_read_required or project_write_required)
    # we could directly set target_for_conditional_access to this_project.owner
    # and resource_for_conditional_access to this_project
    # cap_bypass:to_fix
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  private

  memoize def this_project
    this_user.projects.find_by(number: params[:project_number])
  end

  def this_project_required
    render_404 if this_project.nil?
  end

  def project_read_required
    render_404 unless this_project.readable_by?(current_user)
  end

  def project_write_required
    render_404 unless this_project.writable_by?(current_user)
  end
end
