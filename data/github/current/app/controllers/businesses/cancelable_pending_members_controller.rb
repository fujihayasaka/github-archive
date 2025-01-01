# typed: true
# frozen_string_literal: true

class Businesses::CancelablePendingMembersController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :selected_invitations_required

  def destroy
    selected_invitations.each do |invitation|
      CancelOrganizationInvitationJob.perform_later \
        actor: current_user,
        invitation: invitation,
        notify: false
    end

    flash[:notice] = \
      "Submitted cancellation of member #{"invitation".pluralize(selected_invitations.size)}. \
      It may take a few minutes for the cancellation to process.".squish
    if params[:redirect_to_path].present?
      safe_redirect_to params[:redirect_to_path]
    else
      redirect_to :back
    end
  end

  private

  def selected_invitations_required
    render_404 if selected_invitations.empty?
  end

  memoize def selected_invitations
    this_business.pending_member_invitations.where(id: params[:invitation_ids] || [])
  end
end
