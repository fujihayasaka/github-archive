# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EmailListItemComponent < ApplicationComponent

      sig { params(invitation: T.nilable(OrganizationInvitation), organization: ::Organization, assignable_seat: Copilot::Organizations::SeatManagement::Detail).void }
      def initialize(invitation, organization, assignable_seat)
        @invitation = invitation
        @organization = organization
        @assignable_seat = assignable_seat
      end

      sig { returns(T::Boolean) }
      def render?
        @invitation.present?
      end
    end
  end
end
