# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    module SeatAssignmentHelpers
      extend T::Helpers
      extend self
      include Copilot::Errors
      include Kernel
      include Copilot::Helpers

      abstract!

      # by og_assignment we could mean any non-User assignable_type assignment but naming things is hard
      sig { params(user_id: Integer, seat: Copilot::Seat, non_user_seat_assignment: Copilot::SeatAssignment, event_type: Symbol, actor: T.nilable(::User), owner: T.nilable(T.any(::Business, ::Organization, ::User))).returns(Copilot::SeatAssignment) }
      def create_disassociated_seat_assignment(user_id, seat, non_user_seat_assignment, event_type, actor, owner: nil)
        owner = owner.nil? ? non_user_seat_assignment.owner : owner
        admin = if actor.nil?
          case owner.class.name
          when "Organization"
            owner.admins.first
          when "Business"
            owner.owners.first
          else
            # this should quite literally never happen
            raise Copilot::Errors::SeatAssignmentError.new("Invalid owner type for seat assignment to disassociate from: #{owner.class.name}")
          end
        else
          actor
        end

        # A user may already have an individual seat assignment, or, because we don't control the order jobs run,
        # a user may already have a disassociated user SeatAssignment created by another job.
        # For example:
        #   * User is removed from the organization.
        #   * This triggers the removal of the user from the team.
        #   * The OrganizationRemoveMemberJob runs first, and creates a disassociated user SeatAssignment.
        #   * This job runs, and also tries to create a disassociated user SeatAssignment.
        existing_user_assignment = Copilot::SeatAssignment.find_by(
          owner_type: owner.class.name,
          owner_id: owner.id,
          assignable_type: "User",
          assignable_id: user_id
        )

        with_write do
          user_assignment = if existing_user_assignment.present?
            GitHub.logger.info("User already has User SeatAssignment, not creating one to disassociate.",
              "gh.user.id" => user_id,
              "gh.copilot.seat_assignment.id" => existing_user_assignment.id,
              "gh.seat.id" => seat.id
            )
            existing_user_assignment
          else
            disassociated_user_assignment = Copilot::SeatAssignment.create!(
              owner_type: owner.class.name,
              owner_id: owner.id,
              owner: owner,
              organization: owner.class.name == "Organization" ? owner : nil, # TODO: remove when we remove any reference to organization
              assignable_id: user_id,
              assignable_type: "User",
              assigning_user: owner.member?(non_user_seat_assignment.assigning_user) ? non_user_seat_assignment.assigning_user : admin
            )
            GitHub.logger.info(
              "Created User SeatAssignment to disassociate from #{non_user_seat_assignment.assignable_type}",
              "gh.copilot.seat.id" => seat.id,
              "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id,
            )

            # let's only send this to hydro so we don't confuse users in the audit log
            Copilot::Instrumenter.send_to_hydro(
              Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED, {
                assignment: disassociated_user_assignment,
                owner: owner,
                actor: actor,
                event_type: event_type,
                details: {
                  old_seat_assignment_id: non_user_seat_assignment.id
                }
              }
            )

            disassociated_user_assignment
          end

          user_assignment
        end
      end

      sig { params(user: ::User, non_user_seat_assignment: Copilot::SeatAssignment).returns(T.nilable(Copilot::SeatAssignment)) }
      def other_team_or_enterprise_team_assignment_for_user(user, non_user_seat_assignment)
        case non_user_seat_assignment.assignable_type
        when "Team", "EnterpriseTeam"
          # we've sorted by pending_cancellation_date so the first one should be one that isn't pending cancellation if one exists
          other_team_or_enterprise_team_assignments_for_owner(non_user_seat_assignment.assignable_id, non_user_seat_assignment.owner).find do |team_assignment|
            team_assignment.includes_user?(user)
          end
        else
          raise Copilot::Errors::SeatAssignmentError.new("Cannot find other team assignments for non-team assignable type: #{non_user_seat_assignment.assignable_type}")
        end
      end

      sig { params(team_to_exclude_id: Integer, owner: Copilot::Owner).returns(ActiveRecord::Relation) }
      def other_team_or_enterprise_team_assignments_for_owner(team_to_exclude_id, owner)
        # It would be nice that if there are multiple other team assignments we repoint the seat at one that is not pending cancellation if it exists.
        # so we're sorting records such that those with pending_cancellation_date == nil is first
        case owner.class.name
        when "Organization"
          Copilot::SeatAssignment.team_assignments(owner).where.not(assignable_id: team_to_exclude_id).order("pending_cancellation_date ASC")
        when "Business"
          Copilot::SeatAssignment.enterprise_team_assignments(owner).where.not(assignable_id: team_to_exclude_id).order("pending_cancellation_date ASC")
        else
          # what
          raise Copilot::Errors::SeatAssignmentError.new("Unknown owner type: #{owner.class.name}")
        end
      end
    end
  end
end
