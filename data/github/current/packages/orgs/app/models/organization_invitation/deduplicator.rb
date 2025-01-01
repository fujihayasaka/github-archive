# typed: true
# frozen_string_literal: true

class OrganizationInvitation
  # When there are duplicate invitations for a given user/org, transfer all
  # team_invitations to the invitation the user is accepting and cancel all the
  # duplicate invitations.
  #
  # Note: this is intended to be run inside a transaction where the acceptance
  # of the non-duplicate invitation will either succeed or it (and this
  # destructive action) will be rolled back.
  class Deduplicator
    # Public: See #call!
    def self.call!(invitation:, acceptor:)
      new(invitation: invitation, acceptor: acceptor).call!
    end

    # Public: Initialize the Deduplicator
    #
    # invitation - The OrganizationInvitation we are going to accept
    # acceptor - The User accepting the OrganizationInvitation
    def initialize(invitation:, acceptor:)
      @invitation = invitation
      @acceptor = acceptor
    end

    # Public: When there are duplicates invitations:
    # 1. log pertinent info
    # 2. add each team_invitation for each duplicate to the non-duplicate
    # 3. mark all duplicates as cancelled
    #
    # Examples
    #
    #   call!
    #   # => true
    #
    # Returns TrueClass or raises.
    def call!
      return true unless @invitation.email? || @invitation.organization.org_invite_deduplication_enabled?

      duplicate_invitations.each do |duplicate|
        log(duplicate)
        transfer_team_invitations(duplicate)
        cancel(duplicate)
      end
    end

    private

    def duplicate_invitations
      normalized_emails = if @invitation.organization.org_invite_deduplication_enabled?
        verified_acceptor_email_literals
      else
        acceptor_email_literals
      end

      @invitation
        .organization
        .pending_invitations
        .where.not(id: @invitation.id)
        .with_invitee_or_normalized_email(
          invitee: @acceptor,
          emails: normalized_emails,
      )
    end

    def acceptor_email_literals
      acceptor_emails.pluck(:email)
    end

    def verified_acceptor_email_literals
      acceptor_emails.verified.pluck(:email)
    end

    def acceptor_emails
      @acceptor_emails ||= @acceptor.emails
    end

    def log(duplicate)
      GitHub.logger.info("duplicate_organization_invitations",
        "code.namespace": self.class.to_s,
        "code.function": "call!",
        "gh.acceptor": @acceptor,
        "gh.duplicate.invitee_id": duplicate.invitee_id,
        "gh.duplicate.inviter_id": duplicate.inviter_id,
        "gh.duplicate.email": duplicate.email,
        "gh.duplicate.id": duplicate.id,
        "gh.original.id": @invitation.id,
      )
    end

    # Move all team invitations from duplicates to the non-duplicate
    def transfer_team_invitations(duplicate)
      return if unverified_email_invitation?(duplicate)

      duplicate.team_invitations.each do |team_invitation|
        @invitation.add_team(
          team_invitation.team,
          inviter: team_invitation.inviter,
        )
      end
    end

    # Do _not_ instrument this cancel call since this is internal cleaning up
    # and should not be served to the user as webhook/audit_log entry
    def cancel(duplicate)
      duplicate.cancel(actor: nil, notify: false, instrument: false)
    end

    def unverified_email_invitation?(invitation)
      return false unless invitation.email?

      acceptor_emails.unverified.pluck(:email).include?(invitation.email)
    end
  end
end
