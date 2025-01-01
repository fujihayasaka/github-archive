# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class ExternalIdentityJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      include Copilot::Helpers
      gate_with_feature_flag %i(copilot_seat_assignment_job copilot_external_identity_job)

      sig do
        params(
          user_id: Integer,
          external_identity_id: Integer,
          transaction_id: T.nilable(String),
          action: Symbol,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def perform(user_id:, external_identity_id:, transaction_id: nil, action: :unknown, payload: nil)
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

          case action
          when :deprovision
            handle_deprovision_event(user_id, external_identity_id)
          when :provision
            handle_provision_event(user_id, external_identity_id)
          else
            raise ArgumentError, "Invalid action: #{action}"
          end
        end
      end

      sig { params(user_id: Integer, external_identity_id: Integer).void }
      def handle_deprovision_event(user_id, external_identity_id)
        GitHub.logger.with_named_tags("code.function" => "handle_deprovision_event") do
          # we want to check first if this deprovisioned external identity has any seats
          if Copilot::Seat.where(assigned_user_id: user_id).exists?
            # we've been deprovisioned, suspended, whatever you wanna call it, we need to set ourselves up for cancellation.
            # as an external identity emu whatchacallit, this user can have multiple seats, but they will all be in the same enterprise
            Copilot::Seat.where(assigned_user_id: user_id).each do |seat|
              seat_assignment = seat.seat_assignment
              GitHub.logger.with_named_tags(
                "gh.copilot.seat.id" => seat.id,
                "gh.copilot.seat_assignment.id" => seat_assignment&.id,
                "gh.copilot.seat_assignment.assignable_id" => seat_assignment&.assignable_id,
                "gh.copilot.seat_assignment.assignable_type" => seat_assignment&.symbolized_assignable_type,
                "gh.user.id" => @user_id,
                "gh.copilot.external_identity.id" => @external_identity_id,
                ) do

                GitHub.logger.info("Processing seat")

                unless seat_assignment.present?
                  # not sure how this would happen but let's tell someone and skip this seat,
                  # the DeleteOrphanedSeatsJob will eventually clean it up.
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
                  next
                end

                symbolized_assignable_type = seat_assignment.symbolized_assignable_type
                GitHub.dogstats.increment("copilot.external_identity_job.#{symbolized_assignable_type.downcase}_seat_assignment")

                if seat_assignment.owner.feature_enabled?(:destroy_seats_for_deprovisioned_users)
                  # Let's make sure the user seat assignment is actually pointing at this user
                  if symbolized_assignable_type == :USER && seat_assignment.assignable_id != user_id
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
                    break #sadly
                  end

                  GitHub.logger.info("Canceling deprovisioned user's seat")

                  with_write do
                    seat.cancel!(reason: :user_deprovisioned)
                  end
                else
                  case symbolized_assignable_type
                  when :ENTERPRISE_TEAM
                    # Skipping EnterpriseTeams here because suspended users should be handled by the EnterpriseTeamConverterCommand
                    # when it is called from the EnterpriseTeamJob whenever the EnterpriseTeam is updated (mapping changed)
                    GitHub.logger.info("Skipping seat assignment for enterprise team")
                    GitHub.dogstats.increment("copilot.external_identity_job.enterprise_team_skipped")
                    next
                  when :USER
                    # this is already pointing at a User Seat Assignment, let's make sure that it is this user
                    if seat_assignment.assignable_id != user_id
                      # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
                      # 🚨🚨🚨 What did you do? You shouldn't be here.  🚨🚨🚨
                      # 🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨🚨
                      #
                      # This is really bad.  We should go to the corner and curl into a ball
                      # Instead, we're gonna send an exception to Sentry so an adult can handle this
                      Copilot::ErrorReporter.report!(
                        Copilot::Errors::SeatAssignmentError.new("Seat Assignment pointing at wrong user"),
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
                      GitHub.logger.error("Seat assignment pointing at wrong user")
                      break #sadly
                    end

                    GitHub.logger.info("Unassigning user seat assignment")
                    # so, the user in the external identity is the user in the seat assignment - all is right with the world
                    # let's see if they are already pending cancellation

                    unless seat_assignment.pending_cancellation?
                      with_write do
                        seat_assignment.unassign!(nil, :external_identity_deprovisioned)
                      end
                    end
                  when :TEAM, :ORGANIZATION
                    GitHub.logger.info("Creating new user seat assignment")
                    # we need to create a new seat assignment for this user and remove them from the team assignment
                    # since we checked for an enterprise_team type, this should only be an organization owner
                    user_seat_assignment = Copilot::SeatAssignment.new(
                      owner_id: seat_assignment.owner_id,
                      owner_type: seat_assignment.owner_type,
                      organization_id: seat_assignment.organization_id, # if available
                      assignable: seat.assigned_user,
                      assigning_user: seat_assignment.owner.admins.first,
                      pending_cancellation_date: seat_assignment.owner.next_metered_billing_cycle_starts_at,
                    )
                    user_seat_assignment.skip_delayed_converter_job = true

                    # switch to write connection
                    with_write do
                      user_seat_assignment.save(validate: false)

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
                        actor: nil,
                        event_type: event_type,
                        details: {
                          old_seat_assignment_id: seat_assignment.id
                        }
                      }
                    )

                    # instrument that we set it to pending cancellation
                    Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
                      user_seat_assignment,
                      nil,
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
                          # the team is empty or only includes this user, so we can update and destroy
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
          else
            GitHub.logger.info("Deprovisioned user has no seats")
          end
        end
      end

      sig { params(user_id: Integer, external_identity_id: Integer).void }
      def handle_provision_event(user_id, external_identity_id)
        GitHub.logger.with_named_tags("code.function" => "handle_provision_event") do
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

          # this can be an organization or a business based on the VALID_PROVIDER_TYPES in ExternalIdentity
          # either way, we want the organization ids
          organization_ids = if external_identity.target.is_a?(::Organization)
            [external_identity.target.id]
          elsif external_identity.target.is_a?(::Business)
            external_identity.target.organization_ids
          else
            []
          end

          if organization_ids.empty?
            GitHub.logger.info("User has no organizations")
            return
          end

          # this user could be a member of multiple organizations.
          # one of those organizations could have allowed the entire organization
          # let's check
          org_assignments = Copilot::SeatAssignment.where(
            assignable_id: user.organization_ids,
            assignable_type: "Organization",
            owner_type: "Organization",
            owner_id: organization_ids,
            pending_cancellation_date: nil,
          )

          if org_assignments.any?
            # we have some org level seat assignments
            GitHub.logger.info("User's organizations have org levels seat assignments")
            # process all of the organization assignments
            org_assignments.map do |seat_assignment|
              GitHub.logger.info("Processing org seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.convert_to_seats
            end
          else
            GitHub.logger.info("User's organizations have no org level seat assignments")
          end

          # this user could be a member of multiple teams, so let's see if any of those have been assigned
          team_assignments = Copilot::SeatAssignment.where(
            assignable_id: user.team_ids,
            assignable_type: "Team",
            owner_type: "Organization",
            owner_id: organization_ids,
            pending_cancellation_date: nil,
          )

          if team_assignments.any?
            GitHub.logger.info("User's teams have team level seat assignments")
            # process all of the team assignments
            team_assignments.map do |seat_assignment|
              GitHub.logger.info("Processing team seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.convert_to_seats
            end
          else
            GitHub.logger.info("User's teams have no team level seat assignments")
          end

          # the user could be individually assigned so we'll check those
          user_assignments = Copilot::SeatAssignment.where(
            assignable_id: user.id,
            assignable_type: "User",
            owner_type: "Organization",
            owner_id: organization_ids,
            pending_cancellation_date: nil,
          )

          if user_assignments.any?
            GitHub.logger.info("User has user level seat assignments")
            # process all of the individual assignments
            user_assignments.map do |seat_assignment|
              GitHub.logger.info("Processing user seat assignment", "gh.copilot.seat_assignment.id" => seat_assignment.id)
              seat_assignment.convert_to_seats
            end
          else
            GitHub.logger.info("User has no user level seat assignments")
          end
        end
      end
    end
  end
end
