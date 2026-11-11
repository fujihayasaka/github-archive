# typed: true
# frozen_string_literal: true

class Businesses::Organizations::OwnerInvitationsController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required, only: :destroy
  before_action :sudo_filter
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required
  before_action :require_current_organization
  before_action :require_organization_admin

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot, only: [:new], optional: true

  stylesheet_bundle :signup

  def new
    render "businesses/organizations/invite", locals: {
      current_organization: current_organization,
      # list all invited owners. `reverse` so we show the most-recently-added owner first
      # which will keep the list order consistent between refreshes.
      owner_invitations: current_organization.pending_invitations.
        with_business_role(:admin).includes(:invitee)
    }
  end

  def create
    identifier = params[:member].to_s.strip
    return render_404 if identifier.blank?

    if this_business.bypass_admin_invites?
      owner = User.find_by(login: identifier)
      if owner.present?
        current_organization.add_admin(owner, adder: current_user)
      else
        return render_404
      end
    else
      begin
        if User.valid_email?(identifier)
          current_organization.invite(email: identifier, inviter: current_user, role: :admin, invitation_source: :member)
        elsif invitee = User.find_by(login: identifier)
          current_organization.invite(invitee, inviter: current_user, role: :admin, invitation_source: :member)
        else
          return render_404
        end
      rescue OrganizationInvitation::NoAvailableSeatsError
        flash[:error] = "No seats available to invite that user."
      rescue OrganizationInvitation::AlreadyAcceptedError, OrganizationInvitation::InvalidError,
        ActiveRecord::RecordInvalid, ::OrganizationInvitation::TradeControlsError
        flash[:error] = "User could not be invited."
      end
    end

    redirect_to invite_enterprise_organization_url(this_business, current_organization)
  end

  def destroy
    invitation = current_organization.pending_invitations.with_business_role(:admin).find(params[:invitation_id])

    invitation.cancel(actor: current_user)

    redirect_to invite_enterprise_organization_url(this_business, current_organization)
  end

  private

  def require_organization_admin
    render_404 unless current_organization.adminable_by?(current_user)
  end
end
