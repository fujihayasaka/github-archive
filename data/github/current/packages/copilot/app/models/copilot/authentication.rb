# typed: strict
# frozen_string_literal: true

module Copilot
  class Authentication < ApplicationRecord::Copilot
    # NOTE
    # Writes to this table take place in the github/copilot-activity-service repo.

    include ::Instrumentation::Model
    include Copilot::Helpers

    self.table_name = "copilot_authentications"
    self.strict_loading_by_default = true

    # rubocop:todo Rails/InverseOf
    belongs_to :seat, class_name: "Copilot::Seat", foreign_key: :copilot_seat_id, strict_loading: false
    # rubocop:enable Rails/InverseOf

    sig { params(seat: Copilot::Seat).returns(T.nilable(Copilot::Authentication)) }
    def self.for_seat(seat)
      find_by(copilot_seat_id: seat.id)
    end

    sig { params(organization: ::Organization).returns(ActiveRecord::Relation) }
    def self.for_organization(organization)
      joins(seat: :seat_assignment).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: organization.id })
    end

    sig { params(business: ::Business).returns(ActiveRecord::Relation) }
    def self.for_business(business)
      joins(seat: :seat_assignment).where(copilot_seat_assignments: { owner_type: "Business", owner_id: business.id })
    end

    sig { returns(String) }
    def last_surface_used
      return authentication_details if authentication_details.present?
      "Unspecified surface"
    end
  end
end
