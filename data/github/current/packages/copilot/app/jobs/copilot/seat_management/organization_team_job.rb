# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    # We have three different events that we can receive.
    #
    # :add_member - the user has been added to the team, so we want to see if the team has an assignment to auto-add
    # :remove_member - the user has been removed from the team, so we want to see if the team has an assignment to auto-remove (and disassociated)
    # :destroy_team - the entire team has been destroyed, so we want to see if the team has an assignment and auto-remove members (and disassociated)
    class OrganizationTeamJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers
      gate_with_feature_flag :copilot_seat_assignment_job

      VALID_ACTIONS = T.let(%i[add_member destroy_team remove_member], T::Array[Symbol])

      resolve_tenant_context do |args|
        ::Organization.find_by(id: args[:organization_id])&.business
      end

      sig do
        params(
          organization_id: Integer,
          team_id: Integer,
          user_id: T.nilable(Integer),
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, String]),
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(organization_id:, team_id:, user_id: nil, action: :unknown, transaction_id: nil, payload: nil, actor_id: nil)
        raise ArgumentError, "Invalid action: #{action}" unless VALID_ACTIONS.include?(action)

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.org.id" => organization_id,
          "gh.team.id" => team_id,
          "gh.user.id" => user_id,
          "gh.copilot.job_action" => action,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.actor.id" => actor_id,
        ) do
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @team_id         = T.let(team_id, T.nilable(Integer))
          @user_id         = T.let(user_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))

          @actor = T.let(::User.find_by(id: @actor_id), T.nilable(::User))
          @organization = T.let(::Organization.find_by(id: T.must(@organization_id)), T.nilable(::Organization))

          # Destroy team only requires an actor, as sometimes the organization is already deleted
          if action == :destroy_team
            team_destroyed
            return
          end

          # if we're adding or removing a member from the team we gotta have an Organization with copilot and a User
          return report_error("Invalid Organization") unless @organization

          copilot_organization = Copilot::Organization.new(@organization)
          return GitHub.logger.error("Organization not enabled for CFB") unless copilot_organization.copilot_for_business_enabled?

          @user = T.let(::User.find_by(id: T.must(@user_id)), T.nilable(::User))
          return report_error("Invalid User") unless @user

          GitHub.logger.info("Processing action")
          case action
          when :add_member
            member_added
          when :remove_member
            member_removed
          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      # A member was added to the team. Let's see if we have a team assignment for them to auto-add a seat
      #
      # 1. Get out early if the user already has a Seat (it's either User which is more specific or Organization which means everything is broken)
      # 2. Check for team assignment for Team
      # 3. Create a Seat for them
      sig { void }
      def member_added
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name) do
          team_seat_assignment = Copilot::SeatAssignment.team_assignments(@organization).where(assignable_id: @team_id).first

          unless team_seat_assignment.present?
            GitHub.logger.info("No Team SeatAssignment found")
            return
          end

          existing_seat = Copilot::Seat
            .includes(:seat_assignment)
            .where(organization: T.must(@organization), assigned_user_id: T.must(@user).id)
            .first

          if existing_seat.present?
            GitHub.logger.info("Existing Seat found for User")
            GitHub.dogstats.increment "copilot.organization_team_job.member_added.exists"

            # First, we need to check if the user has an existing seat assignment
            existing_seat_assignment = T.must(existing_seat.seat_assignment)
            existing_assignable_type = existing_seat_assignment.symbolized_assignable_type

            # If this existing seat is already pointed at a user seat assignment that is not pending cancellation,
            # we simply need to reinstate access and return.
            # It is unlikely that access will be revoked with a nil pending_cancellation_date, but we should check.
            # If there is a pending cancellation date, we can ignore it.
            # We will update the existing seat to point at the team seat assignment.
            # This also means we can ignore the access_revoked_at value, the team assignment will confers Copilot access.
            if existing_seat.pending_cancellation_date.nil?
              if existing_seat_assignment.owner.feature_enabled?(:copilot_revokable_access) && existing_assignable_type == :USER
                existing_seat_assignment.reinstate_access!(:org_team_member_added)
                GitHub.dogstats.increment "copilot.organization_team_job.member_added.access_reinstated"
              end
              return
            end

            # if the existing seat for a user is pointed at a user or team seat assignment that is pending cancellation,
            # we need to point that seat at this team's seat assignment.  We hope to all that is holy that we didn't
            # somehow get here while a user has a seat associated with an organization seat assignment for the same organization as this team assignment.
            if [:USER, :TEAM].include?(existing_assignable_type)
              with_write do
                GitHub.logger.info("Existing Seat pending cancellation was found, updating it to point at Team SeatAssignment",
                                  "gh.copilot.seat_assignment.id" => team_seat_assignment.id,
                                  "gh.copilot.other_seat_assignment.id" => existing_seat_assignment.id,
                                  "gh.copilot.seat_assignment.symbolized_assignable_type" => existing_seat_assignment.symbolized_assignable_type,
                                  "gh.copilot.seat.id" => existing_seat.id,
                                  "gh.user.id" => @user&.id)
                existing_seat.update_column(:copilot_seat_assignment_id, team_seat_assignment.id)
                GitHub.dogstats.increment "copilot.organization_team_job.member_added.existing_seat_updated"

                if existing_seat_assignment.seats.empty?
                  GitHub.logger.info("Old SeatAssignment has no associated seats anymore, destroying it.",
                                      "gh.copilot.other_seat_assignment.id" => existing_seat_assignment.id,
                                      "gh.copilot.seat_assignment.id" => team_seat_assignment.id)
                  existing_seat_assignment.destroy!
                end
              end
            end

            # Get out of here, we're done
            return
          end

          # If we got here, we need to create a new seat for the user
          # this will trigger a callback that creates a SeatHistory record
          seat = with_write do
            Copilot::Seat.create!(
              seat_assignment: team_seat_assignment,
              organization: T.must(@organization),
              assigned_user: @user,
            )
          end

          GitHub.logger.info(
            "Created seat for user with Team SeatAssignment",
            "gh.copilot.seat_assignment.id" => team_seat_assignment.id,
            "gh.copilot.seat.id" => seat.id
          )

          Copilot::Instrumenter.instrument_copilot_for_business_seat_added(
            T.must(@organization),
            seat.assigned_user_id,
            @actor || team_seat_assignment.assigning_user,
            :member_added_team
          )

          Copilot::SeatManagement::SeatAssignedJob.perform_later(
            seat.organization_id,
            seat.assigned_user_id,
          )
        end
      end

      # A member was removed from the team. Let's see if we have a Team assignment to auto-remove.
      # 1. If we don't have a Team SeatAssignment, we can get out of the function
      # 2. If we do have a Team SeatAssignment, we need to see if the User has a Seat assigned
      # 3. If they don't have a Seat assigned, get out of the function
      # 4. If we've found a seat:
      #    a. We need to see if there's another team seat assignment we can associate this user's seat with.
      #    b. if there isn't, We need to create a new SeatAssignment for the User so we can unassign it (or find one if it somehow exists already)
      #    c. Update the Seat to reference either the existing other team assignment or the newly created SeatAssignment
      #    d. if a new SeatAssignment was created, we set it to be unassigned
      sig { void }
      def member_removed
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name) do
          team_seat_assignment = Copilot::SeatAssignment.team_assignments(@organization).where(assignable_id: @team_id).first
          user = T.must(@user)

          unless team_seat_assignment.present?
            GitHub.logger.info("No Team SeatAssignment found")
            return
          end

          seat = Copilot::Seat.for_assigned_user_and_owner(user, T.must(@organization)).first
          unless seat.present?
            GitHub.logger.info(
              "User Seat doesn't exist for this organization",
              "gh.user.id" => T.must(@user).id,
            )
            return
          end

          assignment_owner = team_seat_assignment.owner

          # If the user is suspended, and we aren't revoking access, we should cancel their seat and exit
          if user.suspended?
            unless assignment_owner.feature_enabled?(:copilot_revokable_access)
              with_write { seat.cancel!(reason: :suspended_user_in_team) }

              GitHub.logger.info(
                "Seat for suspended user has been canceled",
                "gh.user.id" => T.must(@user).id,
              )
              return
            end
          end

          is_org_member = T.must(@organization).member_ids.include?(user.id)

          # If the revocation flag is active, we should revoke access to the seat if the user is no longer an
          # org member or if the user is suspended, otherwise we created a disassociated seat assignment,
          # but continue to allow access.
          if assignment_owner.feature_enabled?(:copilot_revokable_access)
            repoint_or_disassociate_seat_assignment(
              user,
              team_seat_assignment,
              seat,
              revoke_access: !is_org_member
            )
          # If the flag is disabled, but the user is an org member, we create the disassociated assignment,
          # and continue to allow access
          elsif is_org_member
            repoint_or_disassociate_seat_assignment(user, team_seat_assignment, seat)
          # The flag isn't active and they arent an org member, so maintain existing behavior
          # and delete the seat.
          else
            # if they aren't part of the organization any more, we just kill the seat
            GitHub.logger.info("User is no longer part of organization, destroying seat")
            with_write do
              seat.cancel!(reason: :org_member_removed)
            end

            Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(T.must(@organization_id))
          end
        end
      end

      # A team was destroyed. We should have a moment of silence.
      # 1. We need to check if the team's organization still exists and if not, call the OrganizationCleaner just in case
      # 2. We need to check if there's a Team SeatAssignment for the team and exit if not
      # 3. If there was a Team SeatAssignment and the Organization still exists:
      #    a. We need to unassign the Team SeatAssignment
      #    b. For each seat associated with the Team assignment, we need to check whethere there's another
      #       team assignment the assigned user is a member of in order to point their seat at
      #    c. If there isn't another team assignment, we need to create a User level SeatAssignment for the user in order to unassign it
      #    d. If we created a new User level SeatAssignment, we need to point the seat at it
      #    e. finally, we destroy the team's SeatAssignment
      sig { void }
      def team_destroyed
        GitHub.logger.with_named_tags("code.function" => __method__, "code.namespace" => self.class.name, "gh.team.id" => @team_id) do
          # check if the organization still exists, this job could be running because the organization was deleted, which triggers team deletion
          # The OrganizationCleaner should be a noop in that case, unless there is a race condition
          unless @organization.present?
            GitHub.logger.info("Organization not found, calling OrganizationCleaner")
            Copilot::OrganizationCleaner.call(@organization_id, nil)
            return
          end

          this_team_assignment = Copilot::SeatAssignment
            .for_organization(@organization)
            .where(assignable_type: "Team", assignable_id: @team_id)
            .first

          unless this_team_assignment.present?
            GitHub.logger.info("No Team SeatAssignment found")
            return
          end

          GitHub.logger.info(
            "Team was destroyed. Unassigning Team SeatAssignment",
            "gh.copilot.seat_assignment.id" => this_team_assignment.id,
          )

          with_write do
            # unassign! instruments copilot_for_business_seat_assignment_unassigned
            this_team_assignment.unassign!(@actor, :team_destroyed)

            this_team_assignment.seats.each do |seat|
              assigned_user = seat.assigned_user

              # If the user is suspended, we should cancel their seat and skip to the next seat
              if assigned_user.suspended?
                unless @organization.feature_enabled?(:copilot_revokable_access)
                  seat.cancel!(reason: :suspended_user_in_destroyed_team)

                  GitHub.logger.info(
                    "Seat for suspended user has been canceled",
                    "gh.user.id" => assigned_user.id,
                  )

                  next
                end
              end

              other_team_assignment_for_user = other_team_or_enterprise_team_assignment_for_user(assigned_user, this_team_assignment)

              if other_team_assignment_for_user.present?
                seat.update_column(:copilot_seat_assignment_id, other_team_assignment_for_user.id)
                GitHub.logger.info("Found another Team SeatAssignment to point Seat at",
                                    "gh.copilot.seat_assignment.id" => this_team_assignment.id,
                                    "gh.copilot.other_seat_assignment.id" => other_team_assignment_for_user.id,
                                    "gh.copilot.seat.id" => seat.id,
                                    "gh.user.id" => assigned_user.id)
                GitHub.dogstats.increment "copilot.organization_team_job.team_destroyed.existing_seat_updated"
              else
                revoke_access = !@organization.member_ids.include?(assigned_user.id)
                disassociated_user_assignment = create_disassociated_seat_assignment(assigned_user.id, seat, this_team_assignment, :team_destroyed_disassociate_seat, @actor)

                GitHub.logger.info("Associating user's seat with disassociated SeatAssignment",
                                   "gh.seat.id" => seat.id,
                                   "gh.user.id" => assigned_user.id,
                                   "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id)
                seat.update_column(:copilot_seat_assignment_id, disassociated_user_assignment.id)

                if disassociated_user_assignment.owner.feature_enabled?(:copilot_revokable_access) && revoke_access
                  disassociated_user_assignment.unassign_and_revoke_access!(@actor, :team_destroyed_disassociate_seat)
                else
                  # A suspended user will still be a part of the organization, but the unassign! method will not
                  # destroy an assignment if the assignment's owner is enrolled in the feature flag.
                  # The upcoming SuspendedUserJob will handle revoking access to the seat, on a 3 hour interval.
                  # unassign! instruments copilot_for_business_seat_assignment_unassigned
                  disassociated_user_assignment.unassign!(@actor, :team_destroyed_disassociate_seat)
                end
              end
            end

            this_team_assignment.destroy!

            Copilot::SeatManagement::OrganizationDeduplicateJob.perform_later(@organization.id)
          end
        end
      end

      sig { params(user: ::User, og_team_assignment: Copilot::SeatAssignment, seat: Copilot::Seat, revoke_access: T::Boolean).void }
      def repoint_or_disassociate_seat_assignment(user, og_team_assignment, seat, revoke_access: false)
        # check if there are any other Team seat assignments that include this user

        # It would be nice that if there are multiple other assignments we repoint the seat at one that is not pending cancellation if it exists.
        # so we're sorting records such that those with pending_cancellation_date == nil is first
        existing_team_seat_assignment = other_team_or_enterprise_team_assignment_for_user(user, og_team_assignment)

        if existing_team_seat_assignment.present?
          # we found another team assignment, point the seat at it
          with_write do
            seat.update_column(:copilot_seat_assignment_id, existing_team_seat_assignment.id)
          end
          GitHub.logger.info("Found another Team SeatAssignment to point Seat at",
            "gh.copilot.seat_assignment.id" => og_team_assignment.id,
            "gh.copilot.other_seat_assignment.id" => existing_team_seat_assignment.id,
            "gh.copilot.seat.id" => seat.id,
            "gh.user.id" => user.id
          )
          GitHub.dogstats.increment "copilot.organization_team_job.member_removed.existing_seat_updated"
        else
          disassociated_user_assignment = create_disassociated_seat_assignment(user.id, seat, og_team_assignment, :team_member_removed_disassociate_seat, @actor)

          with_write do
            GitHub.logger.info("Associating user's seat with disassociated SeatAssignment",
              "gh.seat.id" => seat.id,
              "gh.user.id" => user.id,
              "gh.copilot.seat_assignment.id" => disassociated_user_assignment.id
            )

            # TODO: consider only doing this if seat.seat_assingment != disassociated_user_assignment already
            seat.update_column(:copilot_seat_assignment_id, disassociated_user_assignment.id)

            # unassign! instruments copilot_for_business_seat_assignment_unassigned
            if disassociated_user_assignment.owner.feature_enabled?(:copilot_revokable_access) && revoke_access
              disassociated_user_assignment.unassign_and_revoke_access!(@actor, :team_member_removed_disassociate_seat)
            else
              disassociated_user_assignment.unassign!(@actor, :team_member_removed_disassociate_seat)
            end
          end
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.team.id" => @team_id,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::SeatCreationError.new(message), details)
      end
    end
  end
end
