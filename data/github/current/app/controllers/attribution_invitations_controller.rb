# typed: true
# frozen_string_literal: true

class AttributionInvitationsController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :login_required

  def accept # rubocop:todo GitHub/UseRestfulActions
    invitation = current_user.targeted_attribution_invitations.find(params[:id])

    if invitation.can_accept?
      invitation.accept!
      flash[:notice] = "The attribution invitation was successfully accepted"
    else
      flash[:error] = invitation.cannot_accept_reason
    end

    redirect_to org_attribution_invitations_path(invitation.owner)
  end

  def reject # rubocop:todo GitHub/UseRestfulActions
    invitation = current_user.targeted_attribution_invitations.find(params[:id])

    if invitation.can_reject?
      invitation.reject!
      flash[:notice] = "The attribution invitation was successfully rejected"
    else
      flash[:error] = invitation.cannot_reject_reason
    end

    redirect_to org_attribution_invitations_path(invitation.owner)
  end

  private

  # cap_audit:to_fix - These methods redirect to app/controllers/orgs/attribution_invitations_controller.rb, which does apply CAP on the org
  # But, the accept/reject the invitation first. Should TFCA by invitation.owner?
  # Its worth noting there is no check the invitation exists, and I think the controller will 500 if it doesn't
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
  end
end
