# typed: true
# frozen_string_literal: true

module Settings
  class PendingInvitationsComponent < ApplicationComponent

    MAX_PENDING_INVITATIONS = 10

    attr_reader :user

    def initialize(user:)
      @user = user
    end

    def render?
      !GitHub.enterprise?
    end

    def pending_invitations
      org_invitations + repo_invitations
    end

    def org_invitations
      OrganizationInvitation.includes(:organization)
        .pending
        .where(invitee_id: user.id)
        .limit(MAX_PENDING_INVITATIONS)
        .reject { |invite| invite.organization.nil? || T.must(invite.organization).spammy? }
    end

    def repo_invitations
      RepositoryInvitation.includes(repository: :owner)
        .excluding_expired
        .where(invitee_id: user.id)
        .limit(MAX_PENDING_INVITATIONS)
        .reject { |invite| invite.repository.nil? || T.must(invite.repository).owner.nil? || T.must(T.must(invite.repository).owner).spammy? }
    end

    def invitation_component_for(invitation)
      case invitation
      when OrganizationInvitation
        Settings::PendingInvitations::OrganizationInvitationComponent.new(invitation: invitation, user: user)
      when RepositoryInvitation
        Settings::PendingInvitations::RepositoryInvitationComponent.new(invitation: invitation, user: user)
      end
    end

    def show_link(invitation)
      link_to invitation.organization.name, user_path(invitation.organization)
    end
  end
end
