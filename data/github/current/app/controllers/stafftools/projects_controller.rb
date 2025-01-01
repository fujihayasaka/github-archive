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
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

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

    view = create_view_model(
      Stafftools::Projects::ShowView,
      project: project,
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

  private

  def archived_projects_for(owner)
    Archived::Project.where(owner_id: owner.id, owner_type: owner.class)
  end
end
