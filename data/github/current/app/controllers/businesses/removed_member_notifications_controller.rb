# typed: true
# frozen_string_literal: true

class Businesses::RemovedMemberNotificationsController < Businesses::BusinessController
  # This controller allows users to dismiss the banner telling them they were removed from
  # the business for failing the 2FA requirement


  def destroy
    notification = Business::RemovedMemberNotification.new(this_business, current_user)
    notification.dismiss

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
