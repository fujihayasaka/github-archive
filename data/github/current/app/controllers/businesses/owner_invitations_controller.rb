# typed: true
# frozen_string_literal: true

class Businesses::OwnerInvitationsController < Businesses::BusinessController
  include Businesses::AdminInvitationControllerMethods

  before_action :business_admin_invitations_required
  # When users who are not logged in attempt to view a pending invitation,
  # redirect to login with a return_to param.
  before_action :login_required, only: :show
  before_action :find_pending_owner_invitation, only: %i(show update)
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

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "businesses/admins/pending_invitation", locals: {
      invitation: pending_owner_invitation,
      must_enable_two_factor: must_enable_two_factor?,
    }
  end

  def update
    accept_pending_invitation(pending_owner_invitation)
    redirect_to enterprise_path(this_business)
  end

  private

  def find_pending_owner_invitation
    return render_404 unless this_business
    @pending_owner_invitation ||= if email_invitation?
      this_business.invitations.pending
        .with_business_role(Business::OWNER_ROLE).with_token(params[:invitation_token])
    else
      this_business.pending_admin_invitation_for current_user, role: :owner
    end
    @pending_owner_invitation || pending_owner_invitation_not_found
  end
  attr_reader :pending_owner_invitation

  def pending_owner_invitation_not_found
    if this_business.owner?(current_user)
      redirect_to enterprise_path(this_business)
    else
      render_pending_admin_invitation_not_found
    end
  end

  def ensure_two_factor_requirement_is_met
    redirect_to enterprise_owner_invitation_path(this_business) if must_enable_two_factor?
  end
end
