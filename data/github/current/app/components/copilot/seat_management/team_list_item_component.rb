# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class TeamListItemComponent < ApplicationComponent

      sig { params(team: T.nilable(Team), organization: ::Organization, assignable_seat: Copilot::Organizations::SeatManagement::Detail).void }
      def initialize(team, organization, assignable_seat)
        @team = team
        @organization = organization
        copilot_org = Copilot::Organization.new(organization)
        @last_token_activity = T.let(assignable_seat.last_activity_at, Time)
        @assignable_seat = assignable_seat
      end

      sig { returns(T::Boolean) }
      def render?
        @team.present?
      end
    end
  end
end
