# typed: true
# frozen_string_literal: true

class Stafftools::ProjectsController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    only: [:migrate]

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = ["Stafftools::ProjectsController#migrate"]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:permissions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :permissions],
    optional: true

  def index
    if current_repository # Repository owner
      projects = current_repository.projects.order(:number).paginate \
        page: params[:page] || 1,
        per_page: 25

      archived_projects = archived_projects_for(current_repository).order(:number)

      render "stafftools/projects/index",
        layout: "layouts/stafftools/repository/collaboration",
        locals: {
          projects: projects,
          archived_projects: archived_projects,
          owner: current_repository,
        }
    elsif this_user
      projects = this_user.projects.order(:number).paginate \
        page: params[:page] || 1,
        per_page: 25

      archived_projects = archived_projects_for(this_user).order(:number)

      render "stafftools/projects/index",
        layout: "layouts/stafftools/organization/content",
        locals: {
          projects: projects,
          archived_projects: archived_projects,
          owner: this_user,
        }
    else
      render_404
    end
  end

  def show
    project = Project.find(params[:id])
    migrated_memex = project.project_migration&.memex_project

    view = create_view_model(
      Stafftools::Projects::ShowView,
      project: project,
      migrated_memex: migrated_memex
    )
    render "stafftools/projects/show", locals: { view: view }
  end

  def permissions # rubocop:todo GitHub/UseRestfulActions
    project = Project.find(params[:id])

    if project.owner_type == "Repository"
      redirect_to permissions_stafftools_repository_path(project.owner.owner.login, project.owner.name)
    else
      view = create_view_model(
        Stafftools::Projects::PermissionsView,
        project: project,
        page: params[:page] || 1,
        per_page: params[:per_page] || 30,
      )
      render "stafftools/projects/permissions", locals: { view: view }
    end
  end

  def destroy
    project = Project.find(params[:id])
    project.enqueue_delete(actor: current_user)
    flash[:notice] = "Project enqueued for deletion."
    redirect_to :back
  end

  def restore # rubocop:todo GitHub/UseRestfulActions
    project = Archived::Project.find(params[:id])

    if project.enqueue_restore
      flash[:notice] = "Project enqueued for restoration."
    else
      flash[:error] = "There was a problem restoring that project."
    end

    redirect_to :back
  end

  def change_owner # rubocop:todo GitHub/UseRestfulActions
    project = Project.find(params[:id])
    new_owner = case params[:new_owner][:type]
    when "Repository"
      Repositories::Public.find_active!(params[:new_owner][:id])
    when "Organization", "User"
      User.find(params[:new_owner][:id])
    else
      raise "Invalid owner type: #{params[:new_owner][:type]}"
    end

    if project.change_owner!(new_owner: new_owner)
      flash[:notice] = "Project owner updated."
      redirect_to stafftools_project_path(id: project.id)
    else
      flash[:error] = %Q{There was a problem changing the owner of Project "#{project.name}" to #{new_owner}.}
      redirect_to stafftools_project_path(id: project.id)
    end
  end

  def unlock # rubocop:todo GitHub/UseRestfulActions
    project = Project.find(params[:id])
    project.unlock!
    flash[:notice] = "Project has been unlocked."
    redirect_to stafftools_project_path(id: project.id)
  end

  def unlink # rubocop:todo GitHub/UseRestfulActions
    project = Project.find(params[:id])
    repo = Repositories::Public.find_active!(params[:repository_id])
    project.unlink_repository(repo)

    flash[:notice] = "#{repo.name} has been unlinked from this project."
    redirect_to stafftools_project_path(id: project.id)
  end

  def migrate # rubocop:todo GitHub/UseRestfulActions
    project = Project.find(params[:id])
    migrate_project(project)
  end

  private

  def archived_projects_for(owner)
    Archived::Project.where(owner_id: owner.id, owner_type: owner.class)
  end

  # this is mostly the same as the method defined in
  # /workspaces/github/app/controllers/project_controller_actions.rb
  # However, this method does not delete the old memex project before destroying the migration and does not redirect to the new memex project
  def migrate_project(project)
    return render_404 unless logged_in? && project

    if project.project_migration.present?
      unless params[:confirm_remigrate] == "true"
        flash[:error] = "must confirm to delete previous migration"
        redirect_to :back
        return
      end

      # Delete current project migration
      project.project_migration.destroy
    end

    actor = Apps::Privileged::MemexAutomation.bot

    # In user-facing controllers, we will do this initialization asynchronously for big projects. We have less
    # rigorous timeouts in stafftools, and we want to remove the obfuscation of another job, so we want to initialize
    # directly here.
    project_migration = MemexProject::Migrator.initialize!(actor, project)

    if project_migration.save
      MigrateLegacyProjectJob.perform_later(project_migration.id)
      redirect_to :back
    else
      flash[:error] = "Migration failed. Please try again"
    end

    project.close
  end
end
