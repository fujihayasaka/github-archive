# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class ListComponent < ApplicationComponent
      extend T::Sig

      sig { params(organization: ::Organization, display_seats: T.nilable(T::Array[Copilot::Organizations::SeatManagement::Detail]), seats: T::Array[Copilot::Organizations::SeatManagement::Detail], page: Integer, per_page: Integer, pagination_params: T.nilable(T::Hash[Symbol, String])).void }
      def initialize(organization, display_seats, seats, page, per_page, pagination_params: { controller: "seat_management" })
        @organization = organization
        @display_seats = display_seats
        @seats = seats
        @page = page
        @per_page = per_page
        @pagination_params = pagination_params
      end

      sig { returns(T::Boolean) }
      def render?
        @display_seats.present?
      end
    end
  end
end
