# typed: true
# frozen_string_literal: true

module Settings
  module PendingInvitations
    class BaseInvitationComponent < ApplicationComponent

      delegate(
        :avatar_for,
        to: :helpers,
      )

      delegate(
        :can_expire?,
        to: :invitation
      )

      attr_reader :invitation, :user

      def initialize(invitation:, user:)
        @invitation = invitation
        @role = invitation.role
        @user = user
      end

      def show_avatar
        #noop
      end

      def accept_invitation_url
        #noop
      end

      def role_label
        #noop
      end

      def form_method
        :delete
      end

      private

      def remaining_time_message
        return unless invitation.can_expire?

        "Invitation expires in #{expires_in} #{"day".pluralize(expires_in)}"
      end

      def expires_at
        (@invitation.created_at + GitHub.invitation_expiry_period.days).to_date
      end

      def expires_in
        (expires_at - Date.current).to_i
      end
    end
  end
end
