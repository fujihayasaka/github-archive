# typed: strict
# frozen_string_literal: true

module Copilot
  module Payloads
    module Businesses
      class SeatManagement < Copilot::Payloads::Businesses::StandaloneBase
        sig { override.returns(Copilot::Types::StandaloneBusinessSeatManagementIndexPayload) }
        def call
          {
            business: {
              slug: business.slug,
              login: T.cast(business.display_login, String),
            },
            count: all_assignments.count,
            filtered_count: filtered_assignments.count,
            total_seats: Set.new(all_assignments.inject([]) { |list, assignment| list.concat(assignable_from(assignment[:entity]).member_user_ids) }).size,
            seatAssignments: paginated_assignments.map { |assignment| serialized_assignment(assignment) }
          }
        end
      end
    end
  end
end
