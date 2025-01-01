# typed: true
# frozen_string_literal: true

class Stafftools::Users::OperatorModesController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.enable_operator_mode(current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Operator mode enabled.",
    )
  end

  def destroy
    this_user.disable_operator_mode(current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Operator mode disabled.",
    )
  end
end
