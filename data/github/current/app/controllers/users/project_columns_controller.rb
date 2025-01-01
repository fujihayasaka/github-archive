# typed: true
# frozen_string_literal: true

class Users::ProjectColumnsController < Users::Controller
  include ProjectColumnControllerActions
  include SharedProjectControllerActions
  include ProjectsClassicSunset::ProjectsClassicSunsetControllerActions

  before_action :require_projects_classic_ui_enabled_for_current_user
  before_action :hide_spammy_projects
  before_action :this_project_required
  before_action :project_read_required
  before_action :project_write_required, except: [:show]
  before_action :set_client_uid

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:automation_options]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:automation_options, :show], optional: true

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
