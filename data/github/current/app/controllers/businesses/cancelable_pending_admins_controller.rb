# typed: true
# frozen_string_literal: true

class Businesses::CancelablePendingAdminsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :manage_enterprise_admin_invitations_required
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
        errors << "#{current_user} cannot cancel administrator invitations for #{invitation.business.name}."
      end
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = \
        "Submitted cancellation of administrator #{"invitation".pluralize(success.size)}. \
        It may take a few minutes for the cancellation to process.".squish
    end
    redirect_to enterprise_pending_admins_path(this_business)
  end

  private

  memoize def invitations
    this_business.invitations.pending.where(id: params[:invitation_ids])
  end
end
