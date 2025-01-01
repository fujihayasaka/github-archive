# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class SeatsComponent < ApplicationComponent

      PER_PAGE = 10

      sig do
        params(organization: ::Organization,
               page: Integer,
               seat_query: Copilot::SeatManagement::SeatQuery,
               parsed_csv: T.nilable(T::Hash[Symbol, T::Array[T.any(::User, String)]]),
               error: T.nilable(T.any(OrganizationInvitation::InvalidError,
                                      OrganizationInvitation::NoAvailableSeatsError,
                                      OrganizationInvitation::TradeControlsError,
                                      Copilot::Errors::EMUInvitationError)),
               pagination_params: T.nilable(T::Hash[Symbol, String])).void
      end
      def initialize(organization,
                     page = 1,
                     seat_query = Copilot::SeatManagement::SeatQuery.new,
                     parsed_csv = nil,
                     error = nil,
                     pagination_params: nil)
        @organization = organization
        @page = page
        @seat_query = seat_query
        @parsed_csv = parsed_csv
        @error = error
        @pagination_params = pagination_params
        @business_trial = T.let(copilot_organization.business_trial, T.nilable(Copilot::BusinessTrial))
      end

      sig { returns(T::Boolean) }
      def render?
        copilot_organization.copilot_billable? || copilot_organization.business_trial.present?
      end

      private

      sig { returns(T::Boolean) }
      memoize def on_trial
        return false unless copilot_organization.business_trial
        T.must(copilot_organization.business_trial).has_trial?
      end

      sig { returns(Copilot::Organization) }
      memoize def copilot_organization
        Copilot::Organization.new(@organization)
      end

      sig { returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
      memoize def seats
        copilot_organization.seat_assignments(query: @seat_query.query, type: @seat_query.type, sort: @seat_query.sort, direction: @seat_query.direction)
      end

      sig { returns(T.nilable(T::Array[Copilot::Organizations::SeatManagement::Detail])) }
      def display_seats
        seats.slice((@page - 1) * PER_PAGE, PER_PAGE)
      end

      sig { returns(Symbol) }
      def type
        @seat_query.type
      end

      sig { returns(Copilot::Organizations::SeatManagement::SeatBreakdown) }
      def seat_breakdown
        Copilot::Organizations::SeatManagement::SeatBreakdown.new(@organization)
      end
    end
  end
end
