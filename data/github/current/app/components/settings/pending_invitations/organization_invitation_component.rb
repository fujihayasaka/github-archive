# typed: true
# frozen_string_literal: true

module Settings
  module PendingInvitations
    class OrganizationInvitationComponent < BaseInvitationComponent

      def resource
        invitation.organization
      end

      def show_link
        link_to invitation.organization.name, user_path(invitation.organization)
      end

      def accept_invitation_url
        org_show_invitation_path(invitation.organization)
      end

      def reject_invitation_url
        destroy_org_invitation_path(invitation)
      end

      def show_avatar
        avatar_for resource, 20, class: "v-align-middle"
      end

      def role_label
        case @role
        when "admin" then "Owner"
        else
          "Member"
        end
      end
    end
  end
end
