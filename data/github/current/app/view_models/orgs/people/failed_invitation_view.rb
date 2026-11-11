# typed: true
# frozen_string_literal: true

module Orgs
  module People
    class FailedInvitationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :invitation
      attr_reader :organization

      # Public: The member invited by this invitation.
      #
      # Returns a User.
      def member
        invitation.invitee
      end

      def email
        invitation.email
      end

      def email_invitation?
        member.blank?
      end

      def identifier
        if email_invitation?
          email
        else
          member
        end
      end

      def name
        if email_invitation?
          email
        else
          member.profile_name
        end
      end

      def scim_invitation?
        return false if invitation.is_a?(RepositoryInvitation)
        invitation.invitation_source.to_sym == :scim
      end

      # Public: Should admin controls and info be shown in this view?
      #
      # Returns a boolean.
      def show_admin_stuff?
        organization.adminable_by?(current_user)
      end

      # Public: The URL representing this organization member.
      #
      # Returns a string path
      def member_url
        urls.user_path(member)
      end
    end
  end
end
