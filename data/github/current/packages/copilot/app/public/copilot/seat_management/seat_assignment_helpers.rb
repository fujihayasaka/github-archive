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

      sig { params(seat_assignment: Copilot::SeatAssignment, seat: Copilot::Seat, namespace: String, reason: Symbol).returns(T.nilable(Integer)) }
      def revoke_seat_for_user(seat_assignment, seat, namespace, reason)
        GitHub.logger.with_named_tags(
          seat_assignment_log_details(seat.seat_assignment).merge(
            "gh.copilot.seat.id" => seat.id,
            "gh.user.id" => seat.assigned_user_id,
          )
        ) do
          GitHub.logger.info("Unassigning and revoking access for user")
          assignment_id = disassociate_and_revoke_seat(seat, seat_assignment, reason, nil)

          GitHub.dogstats.increment("copilot.seat_management.#{namespace}.access_revoked", tags: ["type:#{seat_assignment.assignable_type.underscore}"])
          assignment_id
        end
      end

      sig { params(seat: Copilot::Seat, original_seat_assignment: Copilot::SeatAssignment, event_type: Symbol, actor: T.nilable(::User), owner: T.nilable(T.any(::Business, ::Organization, ::User)), unassigning_user: T.nilable(::User)).returns(T.nilable(Integer)) }
      def disassociate_and_revoke_seat(seat, original_seat_assignment, event_type, actor, owner: nil, unassigning_user: nil)
        with_write do
          disassociated_assignment = create_disassociated_seat_assignment(seat.assigned_user_id, seat, original_seat_assignment, event_type, actor, owner: owner)

          unless disassociated_assignment == original_seat_assignment
            # update the seat to point to the disassociated assignment
            seat.update_column(:copilot_seat_assignment_id, disassociated_assignment.id)

            GitHub.logger.info("Repointed seat for user to disassociated assignment and revoked access",
              "gh.copilot.original_seat_assignment.id" => original_seat_assignment.id,
              "gh.copilot.seat_assignment.id" => disassociated_assignment.id,
              "gh.user.id" => seat.assigned_user_id,
              "gh.copilot.seat.id" => seat.id,
            )
          end

          disassociated_assignment.unassign_and_revoke_access!(unassigning_user, event_type)

          disassociated_assignment.id
        end
      end

      sig { params(user_id: Integer, seat: Copilot::Seat, original_seat_assignment: Copilot::SeatAssignment, event_type: Symbol, actor: T.nilable(::User), owner: T.nilable(T.any(::Business, ::Organization, ::User))).returns(Copilot::SeatAssignment) }
      def create_disassociated_seat_assignment(user_id, seat, original_seat_assignment, event_type, actor, owner: nil)
        # let's make this idempotent, if the original seat assignment is a user assignment, we can just use it
        if original_seat_assignment.assignable_type == "User" && original_seat_assignment.assignable_id == user_id
          GitHub.logger.info("The seat assignment to disassociate from is already a user-level assignment")
          return original_seat_assignment
        end

        owner = owner.nil? ? original_seat_assignment.owner : owner
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
              "gh.copilot.seat.id" => seat.id
            )
            existing_user_assignment
          else
            disassociated_user_assignment = Copilot::SeatAssignment.new(
              owner_type: owner.class.name,
              owner_id: owner.id,
              owner: owner,
              organization: owner.class.name == "Organization" ? owner : nil,
              assignable_id: user_id,
              assignable_type: "User",
              assigning_user: owner.member?(original_seat_assignment.assigning_user) ? original_seat_assignment.assigning_user : admin,
            )
            # we don't need to convert this seat assignment, we're always pointing an existing seat to it
            disassociated_user_assignment.skip_delayed_converter_job = true
            disassociated_user_assignment.save!

            GitHub.logger.info(
              "Created User SeatAssignment to disassociate from #{original_seat_assignment.assignable_type}",
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
                  old_seat_assignment_id: original_seat_assignment.id
                }
              }
            )

            disassociated_user_assignment
          end

          user_assignment
        end
      end

      # team or enterprise team of course
      sig { params(seat: Copilot::Seat, original_team_assignment: Copilot::SeatAssignment).returns(T::Boolean) }
      def repoint_seat_to_other_team(seat, original_team_assignment)
        entity_type = original_team_assignment.assignable_type

        tags = {
          "gh.copilot.seat.id" => seat.id,
          "gh.user.id" => seat.assigned_user_id,
          "gh.copilot.seat_assignment.id" => original_team_assignment.id,
          "gh.original_#{entity_type.underscore}.id" => original_team_assignment.assignable_id
        }

        # user was probably destroyed
        if seat.assigned_user.nil?
          GitHub.logger.info("No assigned user found for seat associated with #{entity_type} assignment", tags)
          return false
        end

        # The user almost certainly must be here since we just checked if they were nil.
        if T.must(seat.assigned_user).suspended?
          GitHub.logger.info("Assigned user is suspended, not repointing seat to another assignment", tags.merge("user_suspended" => true))
          return false
        end

        other_assignment = other_team_assignment_for_user(T.must(seat.assigned_user), original_team_assignment)

        if other_assignment.present?
          other_assignment_type = other_assignment.assignable_type.underscore
          tags["gh.copilot.other_seat_assignment.id"] = other_assignment.id
          tags["gh.other_#{other_assignment_type}.id"] = other_assignment.assignable_id

          GitHub.dogstats.histogram("copilot.seat_assignment_conversion.existing_seats_updated", 1, tags: ["type:#{other_assignment_type}", "user_suspended:#{seat.assigned_user&.suspended?}"])

          # we found another assignment for the user, point their seat at it
          GitHub.logger.info("Found another #{entity_type} SeatAssignment to point Seat at", tags)
          with_write do
            seat.update_column(:copilot_seat_assignment_id, other_assignment.id)
          end

          true
        else
          false
        end
      end

      sig { params(user: ::User, original_seat_assignment: Copilot::SeatAssignment).returns(T.nilable(Copilot::SeatAssignment)) }
      def other_team_assignment_for_user(user, original_seat_assignment)
        case original_seat_assignment.assignable_type
        when "Team", "EnterpriseTeam", "BusinessTeam"
          # we've sorted by pending_cancellation_date so the first one should be one that isn't pending cancellation if one exists
          other_team_assignments_for_owner(original_seat_assignment.assignable_id, original_seat_assignment.owner).find do |team_assignment|
            team_assignment.includes_user?(user)
          end
        else
          raise Copilot::Errors::SeatAssignmentError.new("Cannot find other team assignments for non-team assignable type: #{original_seat_assignment.assignable_type}")
        end
      end

      # This is used to find other seat assignments for a user in the context of a business.
      # It checks for direct business assignments, org assignments, and finally team assignments.
      # It returns only assignments that are not pending cancellation and are not the original seat assignment.
      sig { params(business: ::Business, user: ::User, original_seat_assignment: Copilot::SeatAssignment).returns(T.nilable(Copilot::SeatAssignment)) }
      def other_business_assignment_for_user(business, user, original_seat_assignment)
        return nil unless business.user_accounts.where(user_id: user.id).exists?

        # Check if the user has a direct business assignment
        if business.can_assign_copilot_to_business_users?
          direct_business_seat_assignments = Copilot::SeatAssignment
            .where(owner: business)
            .where(assignable_type: "User")
            .where(assignable_id: user.id)
            .where.not(id: original_seat_assignment.id)
            .where(pending_cancellation_date: nil)

          return direct_business_seat_assignments.first if direct_business_seat_assignments.any?
        end

        # Check if the user has an org assignment.
        # This filters the assignments to only those that are relevant to the user in the context of the business,
        # so it should be an efficient query.
        user_org_ids = user.organization_ids
        business_org_ids = business.organizations.where(id: user_org_ids).pluck(:id)

        business_org_assignments = Copilot::SeatAssignment
          .where(owner_type: "Organization")
          .where(owner_id: business_org_ids)
          .where.not(id: original_seat_assignment.id)
          .where(pending_cancellation_date: nil)

        return business_org_assignments.first if business_org_assignments.any?

        # Finally look at team assignments. These require looping over each assignment, so this is last.
        if original_seat_assignment.assignable_type.in?(%w[Team EnterpriseTeam BusinessTeam])
          other_team_assignments_for_owner(original_seat_assignment.assignable_id, original_seat_assignment.owner).find do |team_assignment|
            next unless team_assignment.pending_cancellation_date.nil?
            team_assignment.includes_user?(user)
          end
        end
      end

      sig { params(team_to_exclude_id: Integer, owner: Copilot::Owner).returns(ActiveRecord::Relation) }
      def other_team_assignments_for_owner(team_to_exclude_id, owner)
        # It would be nice that if there are multiple other team assignments we repoint the seat at one that is not pending cancellation if it exists.
        # so we're sorting records such that those with pending_cancellation_date == nil is first
        case owner.class.name
        when "Organization"
          Copilot::SeatAssignment.team_assignments(owner).where.not(assignable_id: team_to_exclude_id).order("pending_cancellation_date ASC")
        when "Business"
          # This is the way to check if business teams is enabled. Business teams and enterprise teams are not enabled at the same time.
          if T.cast(owner, ::Business).indirect_abilities_feature_enabled?
            Copilot::SeatAssignment.business_team_assignments(owner).where.not(assignable_id: team_to_exclude_id).order("pending_cancellation_date ASC")
          else
            Copilot::SeatAssignment.enterprise_team_assignments(owner).where.not(assignable_id: team_to_exclude_id).order("pending_cancellation_date ASC")
          end
        else
          # what
          raise Copilot::Errors::SeatAssignmentError.new("Unknown owner type: #{owner.class.name}")
        end
      end

      sig { params(seat_assignment: T.nilable(Copilot::SeatAssignment)).returns(T::Hash[String, T.any(String, Integer)]) }
      def seat_assignment_log_details(seat_assignment)
        {
          "gh.copilot.seat_assignment.id" => seat_assignment&.id,
          "gh.copilot.seat_assignment.owner.id" => seat_assignment&.owner_id,
          "gh.copilot.seat_assignment.owner.type" => seat_assignment&.owner_type,
          "gh.copilot.seat_assignment.assignable.id" => seat_assignment&.assignable_id,
          "gh.copilot.seat_assignment.assignable.type" => seat_assignment&.assignable_type
        }
      end
    end
  end
end
