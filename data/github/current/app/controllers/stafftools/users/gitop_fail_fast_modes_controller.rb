# typed: true
# frozen_string_literal: true

class Stafftools::Users::GitopFailFastModesController < StafftoolsController
  before_action :ensure_user_exists

  def create
    this_user.enable_fail_fast(actor: current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Fail fast mode enabled.",
    )
  end

  def destroy
    this_user.disable_fail_fast(actor: current_user)

    redirect_to(
      stafftools_user_administrative_tasks_path(this_user),
      notice: "Fail fast mode disabled.",
    )
  end
end
