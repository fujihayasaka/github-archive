# typed: true
# frozen_string_literal: true

class Repos::ProjectColumnsController < AbstractRepositoryController
  include ProjectColumnControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :require_projects_classic_ui_enabled_for_current_user
  before_action :require_push_access, except: [:show]
  before_action :set_client_uid
  before_action :require_projects_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:automation_options]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:automation_options, :show],
    optional: true

  def show
    render_show_column(project: this_project)
  end

  def create
    create_project_column(project: this_project)
  end

  def update
    update_project_column(project: this_project)
  end

  def reorder # rubocop:todo GitHub/UseRestfulActions
    reorder_project_columns(project: this_project)
  end

  def archive # rubocop:todo GitHub/UseRestfulActions
    archive_project_column(project: this_project)
  end

  def update_workflow # rubocop:todo GitHub/UseRestfulActions
    update_project_column_workflow(project: this_project)
  end

  def automation_options # rubocop:todo GitHub/UseRestfulActions
    render_project_column_automation_options(project: this_project)
  end

  def destroy
    destroy_project_column(project: this_project)
  end

  private

  memoize def this_project
    current_repository.projects.find_by_number!(params[:project_number])
  end

  def require_push_access
    render_404 unless current_user_can_push?
  end
end
