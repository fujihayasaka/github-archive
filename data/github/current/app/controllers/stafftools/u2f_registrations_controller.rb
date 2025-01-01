# typed: true
# frozen_string_literal: true

class Stafftools::U2fRegistrationsController < StafftoolsController
  before_action :ensure_user_exists

  def destroy
    reason = params[:reason]
    if reason.blank?
      flash[:error] = "You must provide a reason for the log"
      return redirect_back(fallback_location: stafftools_user_security_path(this_user))
    end

    registration = this_user.u2f_registrations.find_by_id!(params[:id])

    nickname = registration.nickname
    registration.destroy

    instrument("staff.passkey_remove", user: this_user, note: reason)
    flash[:notice] = "Passkey #{nickname} removed for @#{this_user}"
    redirect_back(fallback_location: stafftools_user_security_path(this_user))
  end
end
