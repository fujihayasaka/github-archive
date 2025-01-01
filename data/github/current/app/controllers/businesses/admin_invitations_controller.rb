# typed: true
# frozen_string_literal: true

class Businesses::AdminInvitationsController < Businesses::BusinessController
  before_action :business_admin_invitations_required
  before_action :sudo_filter, only: :create
  before_action :manage_enterprise_admin_invitations_required

  def create
    if User.valid_email?(params[:admin])
      invitee = User.find_by_email(params[:admin])
      email = params[:admin]
    else
      invitee = User.find_by(login: params[:admin])
      if invitee.blank?
        flash[:error] = "Could not find user #{params[:admin]} to invite as an administrator"
        return redirect_to enterprise_admins_path(this_business)
      end
    end

    errors = []
    invitation = nil
    begin
      invitation = if invitee.present?
        this_business.invite_admin user: invitee, inviter: current_user, role: params[:role]&.downcase
      else
        this_business.invite_admin email: email, inviter: current_user, role: params[:role]&.downcase
      end
    rescue BusinessAdministratorInvitation::AlreadyAcceptedError,
      BusinessAdministratorInvitation::InvalidError,
      ActiveRecord::RecordInvalid => error
      errors << error.message
    end

    if errors.any?
      flash[:error] = errors.first
      redirect_to enterprise_admins_path(this_business)
    else
      invitation_url = if invitation.owner?
        enterprise_owner_invitation_url(this_business)
      elsif invitation.billing_manager?
        enterprise_billing_manager_invitation_url(this_business)
      end

      extra = "They can also visit #{invitation_url} to accept the invitation."
      notice = <<~NOTICE
        You've invited #{params[:admin]} to become an
        administrator of #{this_business.name}!
        They'll be receiving an email shortly.
        #{extra unless invitation.email.present?}
      NOTICE
      redirect_to enterprise_admins_path(this_business), notice: notice
    end
  end

  def destroy
    invitation = this_business.invitations.pending.find_by!(id: params[:invitation_id])
    errors = []
    begin
      if invitation.cancelable_by?(current_user)
        invitation.cancel actor: current_user
      else
        errors << "#{current_user} cannot cancel administrator invitations for #{invitation.business.name}."
      end
    rescue BusinessAdministratorInvitation::AlreadyAcceptedError
      errors << "This invitation has already been accepted."
    end

    if errors.any?
      flash[:error] = errors.first
    else
      flash[:notice] = \
        "You've canceled #{invitation.email_or_invitee_name}'s invitation to become #{invitation.role_for_message} of #{invitation.business.name}."
    end
    redirect_to enterprise_pending_admins_path(this_business)
  end
end
