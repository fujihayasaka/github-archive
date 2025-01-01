# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class AllListComponent < ApplicationComponent
      extend T::Sig
      sig { returns(::Organization) }
      attr_reader :organization

      sig { returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
      attr_reader :display_seats

      sig { returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
      attr_reader :seats

      sig { returns(Integer) }
      attr_reader :page

      sig { returns(Integer) }
      attr_reader :per_page

      sig do
        params(organization: ::Organization,
               display_seats: T::Array[Copilot::Organizations::SeatManagement::Detail],
               seats: T::Array[Copilot::Organizations::SeatManagement::Detail],
               page: Integer,
               per_page: Integer).void
      end
      def initialize(organization, display_seats, seats, page, per_page)
        @organization = organization
        @display_seats = display_seats
        @seats = seats
        @page = page
        @per_page = per_page
      end
    end
  end
end
