# typed: true
# frozen_string_literal: true

class Orgs::RemovedMemberNotificationsController < Orgs::Controller
  # This controller allows users to dismiss the banner that tells them why they
  # were just removed from an organization (e.g. 2FA or SAML enforcement),
  # which means they won't be a member or have an active external identity
  # session.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def destroy
    notification = Organization::RemovedMemberNotification.new(this_organization, current_user)
    notification.dismiss

    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end
end
