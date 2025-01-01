# typed: true
# frozen_string_literal: true

class MoveWork::MoveWorkController < MoveWork::BaseController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  before_action :ensure_move_work_valid, only: [:show]

  def show
    move_work = current_user.move_work.find(params[:id])
    count_by_type = move_work.total_items_by_resource_type

    if request.xhr?
      return head(202) unless move_work.completed?

      render partial: "move_work/move_work/message", locals: { move_work: move_work, count_by_type: count_by_type }
    else
      render "move_work/move_work/show", locals: { move_work: move_work, count_by_type: count_by_type }
    end
  end

  private

  def ensure_move_work_valid
    move_work = current_user.move_work.find(params[:id])
    render_404 unless move_work.valid?
  end
end
