# typed: true
# frozen_string_literal: true

class Businesses::MemberInvitationsController < Businesses::BusinessController
  include Businesses::AdminInvitationControllerMethods
  include EnterpriseManagedUsersHelper

  before_action :business_supports_unaffiliated_user_accounts_required
  before_action :manage_enterprise_invitations_required, except: %i(show update)
  before_action :business_not_downgraded_to_free_plan_required
  # When users who are not logged in attempt to view a pending invitation,
  # redirect to login with a return_to param.
  before_action :login_required, only: :show
  before_action :find_pending_member_invitation, only: %i(show update)
  before_action :ensure_two_factor_requirement_is_met, only: :update
  before_action :ensure_saml_sso_requirement_is_met, only: :update

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i(show)

  depends_on_clusters \
    ApplicationRecord::Copilot,
    only: %i(show), optional: true

  def show
    render "businesses/member_invitations/show", locals: {
      invitation: pending_member_invitation,
      must_enable_two_factor: must_enable_two_factor?,
    }
  end

  def create
    identifier = (params[:identifier] ||= "").strip
    invitation = if User.valid_email?(identifier)
      BusinessAdministratorInvitation.create(role: :unaffiliated, business: this_business, inviter: current_user, email: identifier)
    else
      invitee = User.find_by_login(identifier)
      BusinessAdministratorInvitation.create(role: :unaffiliated, business: this_business, inviter: current_user, invitee: invitee)
    end
    if invitation.valid?
      flash[:notice] = "Invited #{identifier} to the Enterprise."
    else
      flash[:error] = "Failed to invite #{identifier} to the Enterprise."
    end
    redirect_to people_enterprise_path(this_business)
  rescue BusinessAdministratorInvitation::InvalidError
    render_404
  end

  def update
    accept_pending_invitation(pending_member_invitation)
    redirect_to enterprise_path(this_business)
  end

  private

  def find_pending_member_invitation
    return render_404 unless this_business
    @pending_member_invitation ||= if email_invitation?
      this_business.invitations.pending
        .with_business_role(:unaffiliated).with_token(params[:invitation_token])
    else
      this_business.pending_admin_invitation_for(current_user, role: :unaffiliated)
    end
    @pending_member_invitation || pending_member_invitation_not_found
  end
  attr_reader :pending_member_invitation

  def pending_member_invitation_not_found
    if this_business.member?(current_user)
      redirect_to enterprise_path(this_business)
    else
      render_pending_admin_invitation_not_found
    end
  end

  def ensure_two_factor_requirement_is_met
    redirect_to enterprise_member_invitation_path(this_business) if must_enable_two_factor?
  end

  def business_supports_unaffiliated_user_accounts_required
    return render_404 unless this_business
    render_404 unless this_business.can_invite_unaffiliated_user_accounts?
  end
end
