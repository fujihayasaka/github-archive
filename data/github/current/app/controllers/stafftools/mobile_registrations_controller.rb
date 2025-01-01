# typed: true
# frozen_string_literal: true

class Stafftools::MobileRegistrationsController < StafftoolsController
  before_action :sudo_filter
  before_action :ensure_user_exists

  def destroy
    return render_404 unless this_user&.user?
    id = params[:oauth_access]

    result = this_user.revoke_mobile_device_auth_key(current_user, id, :stafftools)

    if result == :RESULT_SUCCESS
      flash[:notice] = %(Mobile device auth key with oauth_access_id #{id} has been deleted for #{this_user})
    elsif result == :RESULT_FAILED_NOT_FOUND
      flash[:error] = "Mobile device auth key for #{this_user} does not exist."
    elsif result == :RESULT_KEY_ALREADY_REVOKED
      flash[:error] = "Mobile device auth key for #{this_user} was already deleted."
    else
      flash[:error] = "Mobile device auth key for #{this_user} could not be deleted."
    end

    redirect_to :back
  end
end
