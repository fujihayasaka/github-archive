# typed: true
# frozen_string_literal: true

class Businesses::OrganizationMemberInvitationsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :business_owner_required
  before_action :user_or_email_required

  def destroy
    invitations = get_pending_invitations_for(params[:email_or_login])

    if invitations.blank?
      flash[:error] = "No pending invitations found for #{params[:email_or_login]}"
      return redirect_to enterprise_pending_members_path(this_business)
    end

    errors = []

    invitations.each do |invitation|
      begin
        invitation.cancel actor: current_user
      rescue OrganizationInvitation::AlreadyAcceptedError
        errors << "Invitation for #{params[:email_or_login]} to join the enterprise has already been accepted."
      end
    end

    if errors.any?
      # If one of the invites couldn't be revoked, but others succeded, we probably need to give more info than just an error
      flash[:error] = errors.first
    else
      flash[:notice] = \
        "Invitation for #{params[:email_or_login]} to become a member of #{this_business.name} has been canceled."
    end
    redirect_to enterprise_pending_members_path(this_business)
  end

  private

  def user_or_email_required
    if params[:email_or_login].blank?
      flash[:error] = "You must provide a user login or email address to cancel invitations."
      redirect_to enterprise_pending_members_path(this_business)
    end
  end

  def get_pending_invitations_for(user_login_or_email)
    # Do we need to introduce some sort of validation on the email string that is being passed in to prevent bad input?
    user = User.find_by(login: user_login_or_email)

    if user.present?
      this_business.pending_member_invitations.where(invitee_id: user.id)
    else
      this_business.pending_member_invitations.where(email: user_login_or_email)
    end
  end
end
