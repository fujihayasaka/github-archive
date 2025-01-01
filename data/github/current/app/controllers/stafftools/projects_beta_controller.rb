# typed: true
# frozen_string_literal: true

class Stafftools::ProjectsBetaController < StafftoolsController
  before_action :require_project, except: %i[index]
  before_action :ensure_owner_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  DEFAULT_PAGE_SIZE = 25

  def index
    if this_user
      results = get_projects_for_user(params[:query])

      render "stafftools/projects/beta/index",
        layout: "layouts/stafftools/organization/content",
        locals: {
          projects: results[:open_projects],
          owner: this_user,
          closed_projects: results[:closed_projects],
          deleted_projects: results[:deleted_projects],
          query: params[:query]
        }
    else
      render_404
    end
  end

  def show
    content_type_totals = project.memex_project_items.group(:content_type).count
    classic_project_link = project.project_migration ? stafftools_project_path(id: project.project_migration.project&.id) : nil

    render "stafftools/projects/beta/show", locals: {
      project: project,
      project_content_type_totals: content_type_totals,
      classic_project_link: classic_project_link
    }
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    project.destroy
    flash[:notice] = "Project #{project.title} deleted permanently"
    redirect_to :back
  end

  def soft_delete # rubocop:todo GitHub/UseRestfulActions
    project.soft_delete!(current_user)
    flash[:notice] = "Project #{project.title} deleted"
    redirect_to :back
  end

  def reopen # rubocop:todo GitHub/UseRestfulActions
    project.update closed_at: nil
    flash[:notice] = "Project #{project.title} reopened"
    redirect_to :back
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    project.restore!
    flash[:notice] = "Project #{project.title} restored"
    redirect_to :back
  end

  def sync_iteration_fields # rubocop:todo GitHub/UseRestfulActions
    project
      .memex_project_columns
      .iteration
      .each(&:sync_iteration_column_completed_iterations)

    flash[:notice] = "Iteration fields sync successful"
    redirect_to :back
  end

  def rebalance_items # rubocop:todo GitHub/UseRestfulActions
    RebalanceMemexProjectJob.perform_later(project.id, nil)

    flash[:notice] = "Rebalance of memex items in progress"
    redirect_to :back
  end

  def rebalance_views # rubocop:todo GitHub/UseRestfulActions
    RebalanceMemexProjectViewsJob.perform_later(project.id, nil)

    flash[:notice] = "Rebalance of memex views in progress"
    redirect_to :back
  end

  def reindex_items # rubocop:todo GitHub/UseRestfulActions
    status = project.queue_reindex_items

    if status
      flash[:notice] = "Reindexing of memex items in progress"
    else
      flash[:error] = "Reindexing of memex items failed"
    end

    redirect_to :back
  end

  def sync_hierarchy # rubocop:todo GitHub/UseRestfulActions
    SyncMemexProjectHierarchyJob.perform_later(project.id)

    flash[:notice] = "Sync of memex items hierarchy in progress"
    redirect_to :back
  end

  def sync_denormalized_data # rubocop:todo GitHub/UseRestfulActions
    SyncMemexProjectDenormalizedDataJob.perform_later(project.id)

    flash[:notice] = "Sync of memex items denormalized data in progress"
    redirect_to :back
  end

  private

  def get_projects_for_user(query)
    open_projects = this_user.memex_projects.open_projects \
      .where("CONVERT(`title`  USING utf8mb4) LIKE ? OR creator_id = ?", "%#{query}%", query)
      .order(:number).paginate \
      page: params[:open_projects_page] || 1,
      per_page: DEFAULT_PAGE_SIZE

    closed_projects = this_user.memex_projects.closed_projects
      .where("CONVERT(`title`  USING utf8mb4) LIKE ? OR creator_id = ?", "%#{query}%", query)
      .order(:number).paginate \
      page: params[:closed_projects_page] || 1,
      per_page: DEFAULT_PAGE_SIZE

    deleted_projects = this_user.memex_projects.deleted_projects
      .where("CONVERT(`title`  USING utf8mb4) LIKE ? OR creator_id = ?", "%#{query}%", query)
      .order(:number).paginate \
      page: params[:deleted_projects_page] || 1,
      per_page: DEFAULT_PAGE_SIZE

    {
      open_projects: open_projects,
      closed_projects: closed_projects,
      deleted_projects: deleted_projects
    }
  end

  def require_project
    render_404 unless project
  end

  memoize def project
    MemexProject.find(params[:id])
  end

  def ensure_owner_exists
    owner = this_user || project.owner

    render_404 if owner.organization? && owner.soft_deleted?
  end
end
