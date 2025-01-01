# typed: true
# frozen_string_literal: true

module Organization::InvitationsDependency
  include Kernel
  extend T::Helpers
  requires_ancestor { Organization }
  # Public: Invite the specified user to join this org.
  #
  # user    - User to invite to join the organization.
  # email   - Email to invite to join the organization.
  # inviter - User sending the invitation.
  # teams   - Array of teams to invite the user to join.
  # role    - Symbol representing the role the invitee is being invited into.
  #           Can be :direct_member, :admin, :billing_manager or :reinstate.
  # external_identity - ExternalIdentity associated with the organization invitation,
  #           if invited as a result of an external access management change
  # invitation_source - The source of the invitation, e.g. :unknown, :member, :scim.
  #
  # Returns an OrganizationInvitation.
  # Raises TradeControlsError when inviter or invitee have been trade controls restricted
  # Raises NoAvailableSeatsError when there are no seats available
  # Raises NoAvailableSeatsError when no available seats because of pending cycle
  def invite(user = nil, email: nil, inviter:, teams: [], role: nil, external_identity: nil, invitation_source: :unknown)
    role = :direct_member unless OrganizationInvitation.valid_role?(role)
    email = email.presence # force "falsey" values to nil

    if role == :reinstate
      GitHub.dogstats.increment("organization", tags: ["action:invite", "reinstate:true", "by_email:#{email.present?}"])
    else
      GitHub.dogstats.increment("organization", tags: ["action:invite", "reinstate:false", "by_email:#{email.present?}"])
    end

    invitation = T.let(invitations.new(
      invitee: user,
      email: email,
      inviter: inviter,
      role: role,
      external_identity_id: external_identity&.id,
      invitation_source: invitation_source
      ), T.untyped)

    if has_full_trade_restrictions?
      invitation.update!(failed_reason: :trade_controls)
      raise ::OrganizationInvitation::TradeControlsError, TradeControls::Notices.notice_as_plaintext(:organization_account_restricted)
    end

    if role != :billing_manager
      business_or_org_has_seats_for?(invitation: invitation, user: user, email: email)
    end

    ApplicationRecord::Domain::Users.transaction do
      GitHub.dogstats.distribution_time("organization.time", tags: ["action:invite"]) do
        Organization::InviteStatus.new(self, user, email: email, inviter: inviter, teams: teams, role: role, external_identity: external_identity).validate!

        previous_invitation = pending_invitation_for(user, email: email, include_private_emails: false)
        invitation.save! unless previous_invitation.present?
        invitation = previous_invitation || invitation
      end

      invitation.bundled_license_assignments.each do |assignment|
        assignment.touch
        Licensing::SendVssStatusMessageJob.perform_later(assignment: assignment)
      end

      # Filter out duplicates and teams that the user is already invited to.
      teams_to_add = teams.to_a.uniq - invitation.teams.reload
      teams_to_add.each { |team| invitation.add_team(team, inviter: inviter) }

      invitation
    end
  end

  # Public: Returns a scope of invitations
  #
  # actor    - User attempting the action
  # invitation_ids - Invitations to check for.
  #
  # Returns an array of OrganizationInvites.
  def invitations_for(actor, invitation_ids: nil)
    return [] unless self.adminable_by?(actor)

    invitations.where(id: invitation_ids)
  end

  # Public: Returns true if the organization or parent business has enough seats.
  # If not, it will raise an exception if given an invitation; otherwise returns false.
  # invitation – OrganizationInvitation. Optional.
  # user – User. Optional.
  # email – String. Optional.
  # Either user or email must be provided.
  def business_or_org_has_seats_for?(invitation: nil, user: nil, email: nil)
    return true if organization? && business&.has_sufficient_licenses_for?(user: user, email: email)

    error_message = \
    if !has_seat_for?(user)
      "No seats are available to invite this user"
    elsif !has_seat_for?(user, pending_cycle: true)
      "Your organization has a pending seat downgrade. Please cancel your pending change before inviting this user"
    end

    return true if error_message.nil?

    if invitation.present?
      invitation.update!(failed_reason: :no_more_seats)
      raise OrganizationInvitation::NoAvailableSeatsError, error_message
    end
    false
  end

  # Public: Enqueues a job to retry the organization's failed invitations. Will also destroy failed
  # outside collaborator (repository) invitations.
  # actor - User attempting the action
  #
  # Returns nothing.
  def retry_failed_invitations(actor)
    return if !actor.site_admin? && !self.adminable_by?(actor)

    RetryFailedOrganizationInvitationJob.perform_later(self, actor)
    RepositoryBulkInviteJob.perform_later(actor, failed_repo_invitations.pluck(:id))
  end

  # Public: Enqueues a job to destroy the organization's failed invitations. Will also destroy failed
  # outside collaborator (repository) invitations.
  # actor - User attempting the action
  #
  # Returns nothing.
  def destroy_failed_invitations(actor)
    return unless actor.site_admin? || self.adminable_by?(actor)

    DestroyFailedInvitationsToOrgJob.perform_later(self)
    DestroyFailedRepositoryInvitationsToOrgJob.perform_later(self)
  end
end
