# typed: true
# frozen_string_literal: true

class Stafftools::Users::PrivilegedAccessRevocationsController < StafftoolsController
  before_action :ensure_user_exists

  def create
    flash_message = if this_user.revoke_privileged_access(params[:reason])
      { notice: "#{this_user} demoted to a normal user." }
    else
      { error: "You have to specify a reason for the demotion." }
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user), flash: flash_message
  end
end
