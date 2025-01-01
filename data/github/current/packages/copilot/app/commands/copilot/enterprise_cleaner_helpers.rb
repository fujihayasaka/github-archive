# typed: strict
# frozen_string_literal: true

module Copilot
  module EnterpriseCleanerHelpers
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { params(seat_assignment: SeatAssignment, standalone: T.nilable(T::Boolean)).void }
    def destroy_seat_assignment(seat_assignment, standalone: false)
      GitHub.logger.info(
        "Destroying seat assignment",
        "gh.copilot.seat_assignment.id" => seat_assignment.id,
        "gh.copilot.seat_assignment.organization_id" => seat_assignment.organization_id,
        "gh.copilot.seat_assignment.assignable_type" => seat_assignment.assignable_type,
        "gh.copilot.seat_assignment.assignable_id" => seat_assignment.assignable_id,
        "gh.copilot.seat_assignment.owner_id" => seat_assignment.owner_id,
      )

      standalone ? seat_assignment.force_destroy! : seat_assignment.destroy!
    end

    sig { params(type: String, id: T::Array[Integer]).void }
    def destroy_copilot_configuration_for(type, id)
      Copilot::Configuration.where(configurable_type: type, configurable_id: id).each do |configuration|
        GitHub.logger.info(
          "Destroying configuration for #{type.downcase}",
          "gh.copilot.configuration.id" => configuration.id,
          "gh.copilot.configuration.type" => type,
        )
        configuration.destroy!
      end
    end

    sig { params(seat: Copilot::Seat).void }
    def destroy_seat(seat)
      GitHub.logger.info(
        "Destroying seat",
        "gh.copilot.seat.id" => seat.id,
        "gh.copilot.seat.assigned_user_id" => seat.assigned_user_id,
        "gh.copilot.seat.copilot_seat_assignment_id" => seat.copilot_seat_assignment_id,
      )

      # Notify the user that their seat has been removed. Maybe we don't want to do that here?
      seat.cancel!(reason: :enterprise_cleaned)
    end

    sig { params(team_assignment: ::EnterpriseTeamAssignment, business_id: Integer).void }
    def destroy_enterprise_team_assignment(team_assignment, business_id)
      GitHub.logger.info(
        "Destroying team assignment",
        "gh.copilot.enterprise_team_assignment.id" => team_assignment.id,
        "gh.copilot.enterprise_team" => team_assignment.enterprise_team&.id,
        "gh.business.id" => business_id,
      )
      team_assignment.destroy
    end
  end
end
