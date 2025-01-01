# typed: true
# frozen_string_literal: true

class Stafftools::Users::ProfileDataController < StafftoolsController
  before_action :ensure_user_exists
  before_action :ensure_user_suspended

  def destroy
    this_user.user_status&.destroy
    this_user.primary_avatar&.destroy
    this_user.profile&.destroy

    if this_user.reload.profile
      flash[:error] = "something went wrong"
    else
      instrument("staff.scrub_profile", user: this_user, actor: User.staff_user)
      flash[:notice] = "#{this_user} profile scrubbed"
    end

    redirect_to stafftools_user_administrative_tasks_path(this_user)
  end

  private

  def ensure_user_suspended
    unless this_user.suspended?
      redirect_to(
        stafftools_user_administrative_tasks_path(this_user),
        flash: { error: "You must suspend the user first." },
      )
    end
  end
end
