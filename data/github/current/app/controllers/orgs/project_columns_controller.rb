# typed: true
# frozen_string_literal: true

class Orgs::ProjectColumnsController < Orgs::Controller
  include ProjectColumnControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :render_404_unless_projects_classic_ui_enabled_for_current_user
  before_action :project_read_required
  before_action :require_projects_enabled
  before_action :project_write_required, except: %w[show]
  before_action :set_client_uid

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    only: [:automation_options]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :automation_options], optional: true

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
    this_organization.visible_projects_for(current_user).find_by_number!(params[:project_number])
  end

  def project_read_required
    render_404 unless this_project.readable_by?(current_user)
  end

  def project_write_required
    render_404 unless this_project.writable_by?(current_user)
  end
end
