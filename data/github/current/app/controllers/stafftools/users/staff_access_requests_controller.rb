# typed: true
# frozen_string_literal: true

class Stafftools::Users::StaffAccessRequestsController < Stafftools::UsersController
  def create
    reason = params[:notes].present? ? params[:reason].concat(": ", params[:notes]) : params[:reason]

    if reason.blank?
      flash[:error] = "You must provide a reason for this impersonation."
    else
      request = this_user.staff_access_requests.create(
          reason: reason,
          requested_by: current_user,
        )

      if request
        StaffAccessMailer.impersonation_access_requested(request).deliver_later
        flash[:notice] = "Permission for staff to impersonate #{this_user} has been requested."
      end
    end

    redirect_to stafftools_user_overview_path(this_user)
  end

  def destroy
    begin
      current_request.cancel(current_user)
      flash[:notice] = "Request to impersonate #{this_user} has been cancelled."
    rescue StaffAccessRequest::RequestNotActive => e
      flash[:error] = e.message
    end

    redirect_to stafftools_user_overview_path(this_user)
  end

  private

  memoize def current_request
    StaffAccessRequest.find(params[:id])
  end
end
