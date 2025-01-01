# typed: true
# frozen_string_literal: true

class BillingManagers::ShowPendingView < Orgs::Invitations::ShowPendingPageView
  attr_reader :invitation

  def invitation_introduction
    if invitation.show_inviter?
      "#{invitation.inviter.safe_profile_name} has invited you"
    else
      "You’ve been invited"
    end
  end
end
