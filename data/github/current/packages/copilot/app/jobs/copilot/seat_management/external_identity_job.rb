# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class ExternalIdentityJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::SeatAssignments::SeatCreation
      include Copilot::Helpers
      gate_with_feature_flag %i(copilot_seat_assignment_job copilot_external_identity_job)

      resolve_tenant_context do |args|
        user_id = args[:user_id]
        ::User.find_by(id: user_id)&.enterprise_managed_business
      end

      sig do
        params(
          user_id: Integer,
          external_identity_id: Integer,
          transaction_id: T.nilable(String),
          action: Symbol,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(user_id:, external_identity_id:, transaction_id: nil, action: :unknown, payload: nil, actor_id: nil)
        payload ||= {}

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.action" => action,
          "gh.copilot.external_identity.external_id" => payload.fetch(:external_identity_external_id, "unknown"),
          "gh.copilot.external_identity.id" => external_identity_id,
          "gh.copilot.external_identity.provider_type" => payload.fetch(:provider_type, "unknown"),
          "gh.copilot.job_action" => action,
          "gh.copilot.operation" => payload.fetch(:operation, :unknown),
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @user_id              = T.let(user_id, T.nilable(Integer))
          @action               = T.let(action, T.nilable(Symbol))
          @transaction_id       = T.let(transaction_id, T.nilable(String))
          @payload              = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @external_identity_id = T.let(external_identity_id, T.nilable(Integer))
          @actor                = T.let(::User.find_by(id: actor_id), T.nilable(::User))

          case action
          when :provision
            handle_provision_event(user_id, external_identity_id)
          when :deprovision
            handle_deprovision_event(user_id, external_identity_id)
          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      sig { params(user_id: Integer, external_identity_id: Integer).void }
      def handle_deprovision_event(user_id, external_identity_id)
        return unless GitHub.flipper[:copilot_external_identity_job_handle_deprovision].enabled?

        GitHub.logger.with_named_tags("code.function" => "handle_deprovision_event") do
          # we want to check first if this deprovisioned external identity has any seats
          copilot_seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: user_id).to_a

          if copilot_seats.empty?
            GitHub.logger.info("Deprovisioned user has no seats", "gh.user.id" => user_id)
            return
          end

          GitHub.logger.info("Processing Copilot seats and seat assignments for deprovisioned user.",
            "gh.user.id" => user_id, "gh.external_identity.id" => @external_identity_id)

          # We've been deprovisioned, suspended, etc, we need to set ourselves up for cancellation.
          # As an external identity EMU, this user can have multiple seats, but they will all be in the same enterprise.
          copilot_seats.each do |seat|
            seat_assignment = seat.seat_assignment
            GitHub.logger.with_named_tags(
              "gh.copilot.seat.id" => seat.id,
              "gh.copilot.seat_assignment.id" => seat_assignment&.id,
              "gh.copilot.seat_assignment.assignable_id" => seat_assignment&.assignable_id,
              "gh.copilot.seat_assignment.assignable_type" => seat_assignment&.symbolized_assignable_type,
              "gh.user.id" => @user_id,
              "gh.copilot.external_identity.id" => @external_identity_id,
              ) do

              # not sure how this would happen but let's tell someone and skip this seat,
              # the DeleteOrphanedSeatsJob will eventually clean it up.
              if seat_assignment.nil?
                handle_nil_seat_assignment(seat)
                next
              end

              symbolized_assignable_type = seat_assignment.symbolized_assignable_type
              GitHub.dogstats.increment("copilot.external_identity_job.seat_processed_for_deprovisioned", tags: ["type:#{symbolized_assignable_type.downcase}"])

              # Let's make sure the user seat assignment is actually pointing at this user
              if symbolized_assignable_type == :USER && seat_assignment.assignable_id != user_id
                handle_mispointed_seat(seat_assignment, seat)
                break # sadly
              end

              case symbolized_assignable_type
              when :ENTERPRISE_TEAM
                # Skipping EnterpriseTeams here because suspended users should be handled by the EnterpriseTeamConverterCommand
                # when it is called from the EnterpriseTeamJob whenever the EnterpriseTeam is updated (mapping changed)
                GitHub.logger.info("Skipping seat assignment for enterprise team")
                GitHub.dogstats.increment("copilot.external_identity_job.enterprise_team_skipped")
                next
              when :USER
                GitHub.logger.info("Unassigning user seat assignment")
                # so, the user in the external identity is the user in the seat assignment - all is right with the world
                with_write do
                  seat_assignment.unassign!(nil, :external_identity_deprovisioned)
                  # Even if the seat assignment was already pending cancellation, we revoke access because the user is no longer in the external identity.
                  seat_assignment.revoke_access!(:external_identity_deprovisioned) if seat_assignment.owner.feature_enabled?(:copilot_revokable_access)
                end
              when :TEAM, :ORGANIZATION
                GitHub.logger.info("Creating new user seat assignment")
                # we need to create a new seat assignment for this user and remove them from the team assignment
                # since we checked for an enterprise_team type, this should only be an organization owner
                user_seat_assignment = Copilot::SeatAssignment.new(
                  owner_id: seat_assignment.owner_id,
                  owner_type: seat_assignment.owner_type,
                  assignable: seat.assigned_user,
                  assigning_user: seat_assignment.owner.admins.first,
                  pending_cancellation_date: seat_assignment.owner.next_metered_billing_cycle_starts_at,
                )
                user_seat_assignment.skip_delayed_converter_job = true

                # switch to write connection
                with_write do
                  user_seat_assignment.save(validate: false)
                  # Revoking access in a separate step to trigger audit logging
                  user_seat_assignment.revoke_access!(:external_identity_deprovisioned) if user_seat_assignment.owner.feature_enabled?(:copilot_revokable_access)

                  GitHub.logger.info(
                    "Disassociating seat from seat assignment",
                    "gh.copilot.seat_assignment.new_id" => user_seat_assignment.id,
                  )
                  seat.update_column(:copilot_seat_assignment_id, user_seat_assignment.id)
                end

                # let's only send this to hydro so we don't confuse users in the audit log
                event_type = seat_assignment.symbolized_assignable_type == :TEAM ? :team_member_deprovisioned_disassociate_seat : :organization_member_deprovisioned_disassociate_seat
                Copilot::Instrumenter.send_to_hydro(
                  Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED, {
                    assignment: user_seat_assignment,
                    owner: user_seat_assignment.owner,
                    actor: @actor,
                    event_type: event_type,
                    details: {
                      old_seat_assignment_id: seat_assignment.id
                    }
                  }
                )

                # instrument that we set it to pending cancellation
                Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
                  user_seat_assignment,
                  @actor,
                  :external_identity_deprovisioned
                )

                if seat_assignment.symbolized_assignable_type == :TEAM
                  # sometimes teams don't exist when we get here and sometimes this user is the last one in
                  # we check the membership of the team and if it is empty, we can destroy the seat assignment
                  with_read do # make sure we are talking to the replicas to ease load on mysql1
                    # switch to looking up the ids only - speeds a LOT up because we don't have to instantiate the individual team members
                    team_member_ids = seat_assignment.assignable.present? ? seat_assignment.assignable.member_ids : []
                    if team_member_ids.empty? || team_member_ids == [seat.assigned_user_id]
                      GitHub.logger.info("Team is empty, destroying seat assignment")
                      # the team is empty or only includes this user, so we can update and destroy.
                      # If the access_revoked_at flag is active, the user will have already had a
                      # disassociated seat assignment created, and their existing seat will point to that.
                      with_write do
                        seat_assignment.destroy!
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      sig { params(user_id: Integer, external_identity_id: Integer).void }
      def handle_provision_event(user_id, external_identity_id)
        return unless GitHub.flipper[:copilot_external_identity_job_handle_provision].enabled?

        GitHub.logger.with_named_tags(
          "code.function" => "handle_provision_event",
          "gh.user.id" => @user_id,
          "gh.external_identity.id" => @external_identity_id) do
          # let's load up the external identity
          external_identity = ExternalIdentity.find_by(id: external_identity_id)

          unless external_identity
            # we have nothing to do here
            GitHub.logger.error("External identity not found")

            Copilot::ErrorReporter.report!(
              Copilot::Errors::MissingExternalIdentityError.new("External identity not found"),
              extra_details: {
                :action => @action,
                :transaction_id => @transaction_id,
                :payload => @payload,
                "gh.user.id" => @user_id,
                "gh.external_identity.id" => @external_identity_id,
              }
            )
            return # crying
          end

          unless external_identity.user_id == user_id
            # we have nothing to do here
            GitHub.logger.error("External identity and user do not match")

            Copilot::ErrorReporter.report!(
              Copilot::Errors::ExternalIdentityUserMismatchError.new("External identity and user do not match"),
              extra_details: {
                :action => @action,
                :transaction_id => @transaction_id,
                :payload => @payload,
                "gh.user.id" => @user_id,
                "gh.external_identity.id" => @external_identity_id,
              }
            )
            return # weeping
          end

          # okay, we have a user, let's look and see if any of the business' organizations has a seat assignment
          # that affects this User
          # we do not do anything for EnterpriseTeams here YET
          user = T.must(external_identity.user)

          GitHub.logger.info("Processing Copilot seat assignments for provisioned user.",
            "gh.user.id" => user.id, "gh.external_identity.id" => external_identity.id)

          # this can be an organization or a business based on the VALID_PROVIDER_TYPES in ExternalIdentity
          # either way, we want the organization ids
          organization_ids = if external_identity.target.is_a?(::Organization)
            [external_identity.target.id]
          elsif external_identity.target.is_a?(::Business)
            external_identity.target.organization_ids
          else
            []
          end

          # I think we'd hit an ActiveSupport error before we got here
          if organization_ids.empty?
            GitHub.logger.info("Provisioned user has no organizations")
            return
          end

          with_read do
            # this user could be a member of multiple organizations.
            # one of those organizations could have allowed the entire organization
            # let's check
            org_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.organization_ids,
              assignable_type: "Organization",
              owner_type: "Organization",
              owner_id: organization_ids,
            )

            if org_assignments.any?
              insert_seats_for_assignments(user, org_assignments)
            else
              GitHub.logger.info("User's organizations have no org level seat assignments")
            end

            # this user could be a member of multiple teams, so let's see if any of those have been assigned
            team_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.team_ids,
              assignable_type: "Team",
              owner_type: "Organization",
              owner_id: organization_ids
            )

            if team_assignments.any?
              insert_seats_for_assignments(user, team_assignments)
            else
              GitHub.logger.info("User's teams have no team level seat assignments")
            end

            # the user could be individually assigned so we'll check those
            user_assignments = Copilot::SeatAssignment.where(
              assignable_id: user.id,
              assignable_type: "User",
              owner_type: "Organization",
              owner_id: organization_ids,
            )

            if user_assignments.any?
              insert_seats_for_assignments(user, user_assignments)
            else
              GitHub.logger.info("User has no user level seat assignments")
            end
          end
        end
      end

      private

      sig { params(user: ::User, seat_assignments: ActiveRecord::Relation).void }
      def insert_seats_for_assignments(user, seat_assignments)
        seat_assignments.each do |seat_assignment|
          # we want to create a new seat pointing at this seat assignment unless the user already has another seat for the org
          # (i.e. got a seat when the org was re-converted or has already had a seat created for a different team in this org during this job
          if Copilot::Seat.for_assigned_user_and_owner(user, seat_assignment.owner).exists?
            GitHub.logger.info("User already has a seat for this organization")
            next
          end

          assignable_type = seat_assignment.assignable_type

          GitHub.logger.info("Processing #{assignable_type} seat assignment for provisioned user",
                              "gh.copilot.seat_assignment.id" => seat_assignment.id,
                              "gh.team.id" => seat_assignment.assignable_id,
                              "gh.org.id" => seat_assignment.owner_id,
                              "gh.copilot.seat_assignment.assignable_type" => assignable_type)

          # we're not calling convert_to_seats on the seat assignment so we don't mess with the rest of the team/org unnecessarily
          # and do a bunch of extra queries we don't care about. We'll take most of the steps the converter commands do, though.
          valid_seat_assignment = ensure_convertible!(seat_assignment, seat_assignment.symbolized_assignable_type.upcase)
          if valid_seat_assignment.nil?
            GitHub.logger.info("Seat assignment is not convertible")
            next
          end

          insert_seats([{
            assigned_user_id: user.id,
            copilot_seat_assignment_id: valid_seat_assignment.id,
            organization_id: valid_seat_assignment.owner_id
          }], seat_assignment, actor: @actor)
          GitHub.dogstats.increment("copilot.external_identity_job.seat_inserted", tags: ["type:#{seat_assignment.symbolized_assignable_type.downcase}"])
        end
      end

      sig { params(seat_assignment: Copilot::SeatAssignment, seat: Copilot::Seat).void }
      def handle_mispointed_seat(seat_assignment, seat)
        # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
        # 🚨🚨🚨 What did you do? You shouldn't be here.  🚨🚨🚨
        # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
        #
        # This is really bad.  We should go to the corner and curl into a ball
        # Instead, we're gonna send an exception to Sentry so an adult can handle this
        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatAssignmentError.new("Seat Assignment for deprovisioned user is pointing at wrong user"),
          copilot_seat_assignment: seat_assignment,
          copilot_seat: seat,
          extra_details: {
            :action => @action,
            :transaction_id => @transaction_id,
            :payload => @payload,
            "gh.user.id" => @user_id,
            "gh.external_identity.id" => @external_identity_id,
          }
        )
        GitHub.logger.error("Seat Assignment for deprovisioned user is pointing at wrong user")
      end

      sig { params(seat: Copilot::Seat).void }
      def handle_nil_seat_assignment(seat)
        GitHub.logger.error("SeatAssignment not found for deprovisioned user's Seat, skipping it")
        GitHub.dogstats.increment("copilot.external_identity_job.no_seat_assignment_for_seat")
        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatAssignmentError.new("Deprovisioned user's Seat has no associated SeatAssignment"),
          copilot_seat: seat,
          extra_details: {
            :action => @action,
            :transaction_id => @transaction_id,
            :payload => @payload,
            "gh.user.id" => @user_id,
            "gh.external_identity.id" => @external_identity_id,
            }
          )
      end
    end
  end
end
