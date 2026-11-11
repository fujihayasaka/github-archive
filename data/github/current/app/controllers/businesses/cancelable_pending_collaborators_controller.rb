# typed: true
# frozen_string_literal: true

class Businesses::CancelablePendingCollaboratorsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :manage_enterprise_invitations_required
  before_action :business_not_downgraded_to_free_plan_required

  def destroy
    invitations.each do |invitation|
      invitation.enqueue_cancel_invitation(actor: current_user, permit_non_repo_admins: true)
    end

    if invitations.empty?
      flash[:error] = "Something went wrong when cancelling invitations for collaborators."
    else
      flash[:notice] = \
        "Submitted cancellation of collaborator #{"invitation".pluralize(invitations.size)}. \
        It may take a few minutes for the cancellation to process.".squish
    end

    redirect_to enterprise_pending_collaborators_path(this_business)
  end

  private

  memoize def invitations
    this_business.pending_collaborator_invitations.where(id: params[:invitation_ids] || [])
  end
end
