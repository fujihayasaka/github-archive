# typed: true
# frozen_string_literal: true

module Settings
  module PendingInvitations
    class RepositoryInvitationComponent < BaseInvitationComponent

      def resource
        invitation.repository
      end

      def show_link
        link_to invitation.repository.name, repository_path(resource)
      end

      def accept_invitation_url
        repository_invitation_path(resource.owner, resource)
      end

      def reject_invitation_url
        repository_invitation_reject_path(invitation.id)
      end

      def form_method
        :post
      end

      def show_avatar
        avatar_for resource.owner, 20, class: "v-align-middle"
      end
    end
  end
end
