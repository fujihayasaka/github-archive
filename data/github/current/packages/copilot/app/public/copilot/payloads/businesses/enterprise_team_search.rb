# typed: strict
# frozen_string_literal: true

module Copilot
  module Payloads
    module Businesses
      class EnterpriseTeamSearch < Copilot::Payloads::Businesses::StandaloneBase
        EnterpriseMembersSearchPayload = T.type_alias do
          {
            teams: T::Array[Copilot::Types::EnterpriseTeamAssignmentPayload],
            total: Integer
          }
        end

        sig { override.returns(EnterpriseMembersSearchPayload) }
        def call
          {
            teams: paginated_assignments.map do |assignment|
              serialized_assignment(T.let(assignment, SeatAssignmentWithStatus))
            end,
            total: all_assignments.size
          }
        end

        private

        sig { override.returns(T::Array[SeatAssignmentWithStatus]) }
        def all_assignments
          unassigned_teams_with_status = unassigned_teams.map do |team|
            {
              entity: team,
              status: get_enum_field("Unassigned")
            }
          end
          (assignments_with_status + unassigned_teams_with_status).uniq do |obj|
            assignable_from(obj[:entity]).id
          end
        end

        sig { returns(T::Array[EnterpriseTeam]) }
        def unassigned_teams
          business.enterprise_teams.active
            .left_outer_joins(:enterprise_team_assignments)
            .where(enterprise_team_assignments: { id: nil })
            .to_a
        end
      end
    end
  end
end
