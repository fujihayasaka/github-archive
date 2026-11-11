# typed: true
# frozen_string_literal: true

module SignupInvitesMethods
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def process_org_invitation(pending_invitation_token, acceptor)
    return unless pending_invitation_token.presence

    # If this request originated from an organization invitation via email,
    # accept the invitation and redirect to the organization profile page

    # If organization requires email verification to accept the email invite,
    # redirect new user to show_pending page which will prompt them to verify their email
    # If organization has enabled the two factor requirement, don't accept
    # the invitation and instead redirect back to the invitation so that
    # the user can enable 2fa and join the organization.
    #
    # Since the user clicked "Join" to get to this point, accepting is
    # continuing the intent of the user.

    if (pending_invitation = pending_org_invitation(pending_invitation_token))
      if pending_invitation.acceptor_needs_to_verify_email?(acceptor: acceptor)
        return redirect_to show_pending_invitation_page(
          inviting_organization: pending_invitation.organization,
          invitation_token: pending_invitation_token,
          pending_invitation_role: pending_invitation.role)
      end

      if !pending_invitation.organization.two_factor_requirement_met_by?(acceptor) || !logged_in?
        # Add the user to this invite to allow them to accept later in the flow
        pending_invitation.update_attribute(:invitee_id, acceptor.id)

        invitation_path = show_pending_invitation_page(
          inviting_organization: pending_invitation.organization,
          invitation_token: pending_invitation_token,
          pending_invitation_role: pending_invitation.role)

        redirect_path = logged_in? ? invitation_path : login_path(return_to: invitation_path)

        return redirect_to(redirect_path)
      end

      pending_invitation.accept(acceptor: acceptor)
      GitHub.dogstats.increment("organization", tags: ["subject:invitations_by_email", "action:signup"])

      flash[:notice] =
        case pending_invitation.role.to_sym
        when :direct_member
          "You are now a member of #{pending_invitation.organization.safe_profile_name}!"
        when :admin
          "You are now an owner of #{pending_invitation.organization.safe_profile_name}!"
        end

      redirect_to user_url(pending_invitation.organization)
    end
  end

  def process_repo_invitation(repo_invitation_token, acceptor)
    return unless repo_invitation_token.presence

    # If this request originated from an repository invitation via email,
    # accept the invitation and redirect to the repository invitation page
    if (pending_invitation = pending_repo_invitation(repo_invitation_token))
      # Add the user to this invite to allow them to accept later in the flow
      pending_invitation.update!(invitee_id: acceptor.id, email: nil, hashed_token: nil)

      redirect_path = logged_in? ? pending_invitation.permalink : login_path(return_to: pending_invitation.permalink)

      redirect_to redirect_path
    end
  end

  private

  def pending_org_invitation(invitation_token)
    return unless invitation_token.present?
    OrganizationInvitation.pending.find_by_token(invitation_token)
  end

  def pending_repo_invitation(invitation_token)
    return unless invitation_token.present?
    RepositoryInvitation.find_by_token(invitation_token)
  end

  def show_pending_invitation_page(inviting_organization:, invitation_token:, pending_invitation_role:)
    if pending_invitation_role == "billing_manager"
      org_show_pending_billing_manager_invitation_path(
        inviting_organization,
        invitation_token: invitation_token,
      )
    else
      org_show_invitation_path(inviting_organization,
        invitation_token: invitation_token,
       )
    end
  end
end
