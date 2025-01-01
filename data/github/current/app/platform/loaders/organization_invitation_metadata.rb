# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class OrganizationInvitationMetadata < Platform::Loader
      def self.load(organization_id)
        invitations = OrganizationInvitation.where(organization_id: organization_id)
        accepted_invitations_count = invitations.where("accepted_at IS NOT NULL").count
        cancelled_invitations_count = invitations.where("cancelled_at IS NOT NULL").count
        email_invitations_count = invitations.where("email IS NOT NULL").count
        user_invitations_count = invitations.where("invitee_id IS NOT NULL").count

        {
          accepted_invitations_count: accepted_invitations_count,
          cancelled_invitations_count: cancelled_invitations_count,
          email_invitee_invitations_count: email_invitations_count,
          total_invitations_count: invitations.count,
          user_invitee_invitations_count: user_invitations_count,
        }
      end
    end
  end
end
