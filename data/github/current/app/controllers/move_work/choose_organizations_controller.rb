# typed: true
# frozen_string_literal: true

class MoveWork::ChooseOrganizationsController < MoveWork::BaseController
  before_action :require_choose_resources_step_completed

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    choose_organization = MoveWork::ChooseOrganizationForm.new
    organizations = organizations_ignoring_this_organization

    render "move_work/choose_organizations/new", locals: {
      choose_organization: choose_organization,
      organizations: organizations,
      progressbar_value: 30,
      selection_type: "existing"
    }
  end

  def create
    organization = organizations_ignoring_this_organization.find_by(id: choose_organization_params[:organization_id])
    choose_organization = MoveWork::ChooseOrganizationForm.new(organization_id: organization&.id)

    if choose_organization.valid?
      move_work_session["organization_id"] = choose_organization.organization_id

      redirect_to move_work_confirmation_page_path(current_context)
    else
      render "move_work/choose_organizations/new", locals: {
        choose_organization: choose_organization,
        organizations: organizations_ignoring_this_organization,
        progressbar_value: 30,
        selection_type: "existing"
      }
    end
  end

  private

  def require_choose_resources_step_completed
    redirect_to new_move_work_path(current_context) if move_work_session["repository_ids"].blank? && move_work_session["project_ids"].blank?
  end

  def organizations_ignoring_this_organization
    current_user.owned_organizations.where.not(id: current_context.id)
  end

  def choose_organization_params
    params.fetch(:move_work_choose_organization_form, {}).permit(:feature, :organization_id)
  end
end
