# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class ActionBarComponent < ApplicationComponent
      extend T::Sig

      sig { returns(Copilot::Organization) }
      attr_reader :copilot_organization

      sig { returns(T::Boolean) }
      attr_reader :selected_mode

      sig { params(organization: ::Organization, selected_mode: T::Boolean).void }
      def initialize(organization, selected_mode)
        @organization         = organization
        @selected_mode        = selected_mode
        @copilot_organization = T.let(Copilot::Organization.new(@organization), Copilot::Organization)
      end

      sig { returns(T::Boolean) }
      def can_add_people?
        selected_mode
      end

      sig { returns(T::Boolean) }
      def can_add_teams?
        @selected_mode && @organization.teams.any?
      end

      sig { returns(T::Boolean) }
      def can_create_team?
        @selected_mode
      end

      private

      sig { returns(T::Boolean) }
      memoize def on_business_trial?
        copilot_organization.on_free_trial?
      end

      sig { returns(Integer) }
      memoize def seat_count
        Copilot::Seat.for_organization(@organization).count
      end
    end
  end
end
