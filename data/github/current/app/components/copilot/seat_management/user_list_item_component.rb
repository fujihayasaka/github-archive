# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class UserListItemComponent < ApplicationComponent

      sig { params(user: T.nilable(::User), organization: ::Organization, assignable_seat: Copilot::Organizations::SeatManagement::Detail).void }
      def initialize(user, organization, assignable_seat)
        @user = user
        @organization = organization
        @assignable_seat = assignable_seat
        copilot_org = Copilot::Organization.new(organization)
        @last_token_activity = T.let(@assignable_seat.last_activity_at, Time)
      end

      sig { returns(T::Boolean) }
      def render?
        @user.present?
      end
    end
  end
end
