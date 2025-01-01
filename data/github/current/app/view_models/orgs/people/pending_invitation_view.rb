# typed: true
# frozen_string_literal: true

module Orgs
  module People
    class PendingInvitationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include Orgs::People::RoleDescriptionMethods
      include Orgs::People::RoleNameMethods

      attr_reader :invitation
      attr_reader :organization
      attr_reader :direct_or_team_member

      # Public: The member invited by this invitation.
      #
      # Returns a User.
      def member
        invitation.invitee
      end

      def email
        invitation.email
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

      def email_invitation?
        member.blank?
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

      # Public: The URL representing the inviter.
      #
      # Returns a string path
      def inviter_url
        urls.user_path(invitation.inviter)
      end

      # Public: What's this member's role?
      #
      # Returns a OrganizationInvitation::Role.
      def role
        @role ||= OrganizationInvitation::Role.new(invitation, organization)
      end

      def direct_or_team_member?
        @direct_or_team_member
      end
    end
  end
end
