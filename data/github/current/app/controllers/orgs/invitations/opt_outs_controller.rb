# typed: true
# frozen_string_literal: true

class Orgs::Invitations::OptOutsController < Orgs::Controller
  include Orgs::InvitationsControllerMethods

  limit_invitation_roles :admin, :direct_member, :reinstate

  # The following actions do not require conditional access checks:
  #
  # - new: serves GET `/orgs/:org/opt-out, shows a
  #   confirmation page and allows users to confirm their consent to opt-out of
  #   future invitations.
  # - create: serves POST `/orgs/:org/opt-out`, allows a user to opt out of
  #   invitations from an organization, an anti-abuse operation that shouldn't
  #   require the user to SSO to perform (and may not be possible).
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(new create)

  before_action :find_pending_invitation, only: %i(new create)

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:new]
  depends_on_clusters ApplicationRecord::Copilot, only: [:new], optional: true

  def new
    view = create_view_model(
      Orgs::Invitations::OptOutConfirmationView,
      invitation: pending_invitation,
      invitation_token: params[:invitation_token]
    )
    render "orgs/invitations/opt_out_confirmation", locals: { view: view }
  end

  def create
    pending_invitation.opt_out(actor: current_user)

    anonymous_flash[:notice] = "You've opted out of receiving invitations from this organization."
    redirect_to user_path(this_organization)
  end

  private

  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    true
  end
end
