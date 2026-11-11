# typed: true
# frozen_string_literal: true

class MoveWork::ConfirmationsController < MoveWork::BaseController
  before_action :require_previous_step_completed

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
    move_work = build_move_work
    render "move_work/confirmations/new", locals: {
      progressbar_value: 90,
      move_work: move_work,
      repos_count: move_work_session["repository_ids"]&.length,
      projects_count: move_work_session["project_ids"]&.length,
    }
  end

  def create
    move_work = build_move_work

    if move_work.save
      move_work.start!
      redirect_to move_work_path(move_work)
    else
      flash[:error] = "Something went wrong. Please try again."
      redirect_to move_work_confirmation_page_path(current_context)
    end
  end

  private

  def build_move_work
    move_work_items = []
    move_work_items += move_work_session["repository_ids"].map { |repository_id| MoveWorkItem.new(resource_id: repository_id, resource_type: "Repository") } if move_work_session["repository_ids"]
    move_work_items += move_work_session["project_ids"].map { |project_id| MoveWorkItem.new(resource_id: project_id, resource_type: "Project") } if move_work_session["project_ids"]

    MoveWork.new(
      user: current_user,
      origin: current_context,
      target_id: move_work_session["organization_id"],
      move_work_items: move_work_items,
      feature: move_work_session["feature"],
    )
  end

  def require_previous_step_completed
    redirect_to new_move_work_path(current_context) if move_work_session["organization_id"].blank?
  end
end
