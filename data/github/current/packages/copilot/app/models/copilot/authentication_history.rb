# typed: strict
# frozen_string_literal: true

module Copilot
  class AuthenticationHistory < ApplicationRecord::Copilot
    # NOTE
    # Writes to this table take place in the github/copilot-activity-service repo.

    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_authentication_histories"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :seat, class_name: "Copilot::Seat", foreign_key: :copilot_seat_id, strict_loading: false
    # rubocop:enable Rails/InverseOf

    sig { params(seat: Copilot::Seat).returns(ActiveRecord::Relation) }
    def self.for_seat(seat)
      Copilot::AuthenticationHistory.where(copilot_seat_id: seat.id)
    end

    sig { params(seat: Copilot::Seat, date: Date).returns(ActiveRecord::Relation) }
    def self.for_seat_and_date(seat, date)
      Copilot::AuthenticationHistory.where(copilot_seat_id: seat.id, authentication_date: date)
    end

    sig { params(organization: ::Organization).returns(ActiveRecord::Relation) }
    def self.for_organization(organization)
      joins(seat: :seat_assignment).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: organization.id })
    end

    sig { params(business: ::Business).returns(ActiveRecord::Relation) }
    def self.for_business(business)
      joins(seat: :seat_assignment).where(copilot_seat_assignments: { owner_type: "Business", owner_id: business.id })
    end
  end
end
