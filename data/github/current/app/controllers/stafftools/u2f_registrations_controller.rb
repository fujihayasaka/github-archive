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
    credential_type = registration.is_passkey_registration? ? "Passkey" : "Security key"
    instrument_event = registration.is_passkey_registration? ? "staff.passkey_remove" : "staff.security_key_remove"
    registration.destroy

    instrument(instrument_event, user: this_user, note: reason)
    flash[:notice] = "#{credential_type} #{nickname} removed for @#{this_user}"
    redirect_back(fallback_location: stafftools_user_security_path(this_user))
  end
end
