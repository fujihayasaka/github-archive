# typed: strict
# frozen_string_literal: true
module Settings
  module PendingInvitations
    class BusinessInvitationComponent < ApplicationComponent
      include ApplicationComponent::Rescuable

      rescue_from StandardError, with: :nothing

      sig { returns T.nilable(User) }
      attr_reader :user

      sig { returns BusinessAdministratorInvitation }
      attr_reader :invitation

      sig { returns T.nilable(Business) }
      attr_reader :business

      sig { returns String }
      attr_reader :role

      sig do
        params(
          invitation: BusinessAdministratorInvitation,
          user: T.nilable(User),
          system_arguments: T.untyped
        ).void
      end
      def initialize(invitation:, user: nil, **system_arguments)
        @user = user
        @invitation = invitation
        @business = T.let(invitation.business, T.nilable(Business))
        @role = T.let(invitation.role, String)
      end

      sig { returns T::Boolean }
      def render?
        return false unless @user
        return false unless @business
        return false unless invitation_is_valid?
        true
      end

      private

      sig { returns(String) }
      def role_label
        case @role
        when "owner" then "Owner"
        when "billing_manager" then "Billing Manager"
        else
          "Member"
        end
      end

      sig { returns(String) }
      def accept_url
        case @role
        when "owner" then enterprise_owner_invitation_path(@business)
        when "unaffiliated" then enterprise_member_invitation_path(@business)
        when "billing_manager" then enterprise_billing_manager_invitation_url(@business)
        else
          enterprise_path(@business)
        end
      end

      sig { returns T.nilable(String) }
      def remaining_time_message
        "Invitation expires in #{expires_in} #{"day".pluralize(expires_in)}"
      end

      sig { returns T::Boolean }
      def invitation_is_valid?
        # Sometimes invitations are not expired via job at the 7 day mark
        # This is an extra check so we never render an invitation with negative time left
        return false unless days_left = expires_in
        return false if days_left < 0
        true
      end

      sig { returns T.nilable(Date) }
      def expires_at
        return nil unless created = @invitation.created_at
        (created + GitHub.invitation_expiry_period.days).to_date
      end

      sig { returns T.nilable(Integer) }
      def expires_in
        return nil unless expires = expires_at
        r = T.cast((expires - Date.current), Rational)
        r.to_i
      end
    end
  end
end
