# typed: true
# frozen_string_literal: true

class MoveWork::ChooseResourcesController < MoveWork::BaseController
  javascript_bundle "pricing"
  javascript_bundle "billing"
  stylesheet_bundle "pricing"
  stylesheet_bundle "site"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    choose_resources = MoveWork::ChooseResourcesForm.new
    view = Orgs::SetupView.new(current_user: current_user, plan: current_context.plan, organization: current_context)

    render "move_work/choose_resources/new", locals: {
      choose_resources: choose_resources,
      progressbar_value: 10,
    }
  end

  def create
    repository_ids = current_context.repositories.where.not(id: current_context.configuration_repository&.id).where(id: choose_resources_params[:repository_ids]).pluck(:id)
    project_ids = current_context.projects.where(id: choose_resources_params[:project_ids]).pluck(:id)

    choose_resources = MoveWork::ChooseResourcesForm.new(repository_ids: repository_ids, project_ids: project_ids)

    if choose_resources.valid?
      session[:move_work] = {
        "repository_ids" => repository_ids,
        "project_ids" => project_ids,
        "feature" => choose_resources_params[:feature]
      }

      redirect_to move_work_new_choose_organization_path(current_context, feature: choose_resources_params[:feature])
    else
      render "move_work/choose_resources/new", locals: {
        choose_resources: choose_resources, progressbar_value: 10 }
    end
  end

  private

  def choose_resources_params
    params.fetch(:move_work_choose_resources_form, {}).permit(:feature, repository_ids: [], project_ids: [], memex_project_ids: [])
  end
end
