# typed: true
# frozen_string_literal: true

class Businesses::CancelablePendingUnaffiliatedMembersController < Businesses::BusinessController
  before_action :business_supports_unaffiliated_user_accounts_required
  before_action :manage_enterprise_invitations_required
  before_action :business_not_downgraded_to_free_plan_required

  def destroy
    errors = []
    success = []
    invitations.each do |invitation|
      if invitation.cancelable_by?(current_user)
        if invitation.accepted?
          errors << "This invitation has already been accepted."
        else
          CancelBusinessAdministratorInvitationJob.perform_later \
            actor: current_user,
            invitation: invitation
          success << invitation
        end
      else
        errors << "#{current_user} cannot cancel unaffiliated member invitations for #{invitation.business.name}."
      end
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = \
        "Submitted cancellation of unaffiliated member #{"invitation".pluralize(success.size)}. \
        It may take a few minutes for the cancellation to process.".squish
    end
    redirect_to enterprise_pending_unaffiliated_members_path(this_business)
  end

  private

  memoize def invitations
    this_business.invitations.pending.with_business_role(:unaffiliated).where(id: params[:invitation_ids])
  end

  def business_supports_unaffiliated_user_accounts_required
    return render_404 unless this_business
    render_404 unless this_business.can_invite_unaffiliated_user_accounts?
  end
end
