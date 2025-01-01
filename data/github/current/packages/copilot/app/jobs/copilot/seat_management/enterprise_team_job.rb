# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class EnterpriseTeamJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      gate_with_feature_flag :copilot_enterprise_team_job
      skip_chatterbox_for_errors true

      resolve_tenant_context do |args|
        ::EnterpriseTeam.find_by(id: args[:team_id])&.business
      end

      sig do
        params(
          team_id: Integer,
          action: T.nilable(Symbol),
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, String]),
        ).void
      end
      def perform(team_id:, action:, transaction_id: nil, payload: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.enterprise_team.id" => team_id,
          "gh.copilot.action" => action,
          "gh.instrumentation.transaction_id" => transaction_id,
        ) do
          @team_id         = T.let(team_id, T.nilable(Integer))
          @team            = T.let(::EnterpriseTeam.find_by(id: @team_id), T.nilable(EnterpriseTeam))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped

          tell_slack("Processing #{@action} event for EnterpriseTeam #{@team_id}")

          case action
          when :enterprise_team_assigned
            return report_error(Copilot::Errors::MissingEnterpriseTeamError.new("Missing Enterprise Team")) unless @team.present? # we require this
            handle_create_event(@team)
          when :update, :enterprise_team_updated
            return report_error(Copilot::Errors::MissingEnterpriseTeamError.new("Missing Enterprise Team")) unless @team.present? # we require this
            handle_update_event(@team)
          when :enterprise_team_unassigned
            handle_unassign_event(T.must(@team_id))
          end
        end
      end

      # When the EnterpriseTeam is created, we will create a SeatAssignment for this EnterpriseTeam
      # - That creation will trigger a background job that will wait 15 minutes and then convert it to seats
      # - If a user from the Team accesses Copilot, we will immediately convert it to seats
      #
      # If the Seat Assignment already exists, and has a pending cancellation date, we assume that the
      # business admin wants to reassign an assigment.
      sig { params(team: EnterpriseTeam).void }
      def handle_create_event(team)
        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.enterprise_team.id" => team.id,
          "gh.enterprise_team.slug" => team.slug
        ) do
          GitHub.logger.info("Handling Create Event")

          assignment = Copilot::SeatAssignment.for_enterprise_team(team).first

          # check if an assignment exists
          if assignment.present?
            return log_assignment_exists(team, assignment) unless assignment.pending_cancellation_date.present?

            refresh_seat_assignment(team, assignment)
          else
            GitHub.logger.info("Creating SeatAssignment for Enterprise Team")
            tell_slack("Creating SeatAssignment For EnterpriseTeam #{team.id}-#{team.slug}")

            with_write do
              # let's create the seat assignment
              new_assignment = Copilot::SeatAssignment.create_for_enterprise_team!(team)

              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(
                new_assignment,
                T.must(team.business).owners.first,
                :direct_assignment,
              )

              GitHub.logger.info(
                "Created SeatAssignment for EnterpriseTeam",
                "gh.copilot.seat_assignment.id" => new_assignment.id,
              )
              tell_slack("Created SeatAssignment #{new_assignment.id} For EnterpriseTeam (#{team.id}-#{team.slug})")
            end
          end
        end
      end

      # When the EnterpriseTeam is updated (which happens when the mappings are updated),
      # we will immediately update from the idp group
      # (deleting any seats that have no associated user - ending access AND billing)
      sig { params(team: EnterpriseTeam).void }
      def handle_update_event(team)
        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.enterprise_team.id" => team.id,
          "gh.enterprise_team.slug" => team.slug,
        ) do
          GitHub.logger.info("Handling Update Event")

          # check if an assignment exists
          if Copilot::SeatAssignment.for_enterprise_team(team).exists?
            # we will just convert it
            assignment = Copilot::SeatAssignment.for_enterprise_team(team).first!

            GitHub.logger.info(
              "Updating SeatAssignment for EnterpriseTeam",
              "gh.copilot.seat_assignment.id" => assignment.id,
            )
            tell_slack("Updating SeatAssignment #{assignment.id} For EnterpriseTeam (#{team.id}-#{team.slug}) - Converting to seats")

            with_write do
              assignment.convert_to_seats # this is idempotent so we can rock it
            end
          else
            # so, we are in another one of those confusing/awkward places
            # we received a notification for a copilot_enterprise_team.update, but we don't have a SeatAssignment
            # for this EnterpriseTeam? Something is going on
            # let's log this and send an error
            report_error(
              Copilot::Errors::MissingEnterpriseTeamSeatAssignmentError.new("SeatAssigment for EnterpriseTeam does not already exist but update event emitted"),
              {
                team: team
              }
            ) # this sends to slack and logs error too
          end
        end
      end

      # This runs when the enterprise_team.copilot.unassignment event is emitted by the destruction of a EnterpriseTeamAssignment
      # The EnterpriseTeam's seat assignment with either be destroyed or have its pending_cancellation_date set depending on
      # when it was created.
      sig { params(team_id: Integer).void }
      def handle_unassign_event(team_id)
        GitHub.logger.with_named_tags(
          "code.function" => __method__,
          "code.namespace" => self.class.name,
          "gh.enterprise_team.id" => team_id,
          "gh.enterprise_team.slug" => @team&.slug,
        ) do
          GitHub.logger.info("Handling Unassignment Event")

          seat_assignment = Copilot::SeatAssignment.for_enterprise_team_id(team_id).first

          return log_missing_assignment(team_id) unless seat_assignment.present?
          return report_error(Copilot::Errors::MissingBusinessError.new("No Business for SeatAssignment linked to EnterpriseTeam #{team_id}")) unless seat_assignment.owner.present?

          assigning_user = seat_assignment.assigning_user || @team&.business&.owners.first


          with_write do
            if seat_assignment.in_cooldown_period? && seat_assignment.owner&.feature_enabled?(:copilot_destroy_seat_assignment_in_cooldown_period)
              GitHub.logger.info(
                "Destroying EnterpriseTeam SeatAssignment that was unassigned in cooldown period.",
                "gh.copilot.seat_assignment.id" => seat_assignment.id,
                "gh.enterprise_team.id" => team_id,
              )

              Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
                seat_assignment,
                assigning_user,
                :unassigned_during_cooldown, # event_type is not allowlisted and the user won't see it
                { unassigned_during_cooldown: true } # the user will see this in the audit log API and UI
              )

              seat_assignment.destroy!
              return
            end

            GitHub.logger.info(
              "Setting pending_cancellation_date SeatAssignment for EnterpriseTeam",
              "gh.copilot.seat_assignment.id" => seat_assignment.id,
              "gh.enterprise_team.id" => team_id,
            )

            tell_slack("Setting pending_cancellation_date for SeatAssignment #{seat_assignment.id} for EnterpriseTeam #{team_id}")
            seat_assignment.update!(pending_cancellation_date: seat_assignment.owner.next_metered_billing_cycle_starts_at)
          end

          assigning_user = seat_assignment.assigning_user || @team&.business&.owners.first
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
            seat_assignment,
            assigning_user,
            :enterprise_team_unassigned
          )
        end
      end

      sig { params(error: Copilot::Errors::CopilotError, details: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
      def report_error(error,  details = {})
        details = details.merge({
          :transaction_id => @transaction_id,
          :payload => @payload,
          :action => @action,
          "gh.team.id" => @team_id,
          :team => @team
        })
        tell_slack(error.message)
        GitHub.logger.error(error.message)
        handle_copilot_error(error, details)
      end

      sig { params(message: String).void }
      def tell_slack(message)
        message = "#{message} (Payload: #{@payload})"
        Copilot::Helpers.force_chatterbox_say!(message, room_id: "#copilot-standalone-ops")
      end

      sig { params(team_id: Integer).void }
      def log_missing_assignment(team_id)
        # so, we are in another one of those confusing/awkward places
        # we received a notification that this EnterpriseTeam was deleted and that it was a CFB team
        # but we don't have a SeatAssignment to work with.
        # so what do we do?  we may have a bunch of Seats without user accounts.
        # we should probably load all Seats with this team's member ids
        report_error(
          Copilot::Errors::MissingEnterpriseTeamSeatAssignmentError.new("SeatAssignment for EnterpriseTeam does not already exist but destroy event emitted"),
          {
            team_id: team_id
          }
        ) # this sends to slack and logs error too
      end

      sig { params(team: EnterpriseTeam, assignment: Copilot::SeatAssignment).void }
      def log_assignment_exists(team, assignment)
        # this is a little awkward - we are getting the :create event but already handled it?
        # we need to log this, send an error to Sentry and yell into Slack
        report_error(
          Copilot::Errors::EnterpriseTeamSeatAssignmentExistsError.new("SeatAssignment for EnterpriseTeam already exists but create event emitted"),
          {
            seat_assignment: assignment,
            team: team
          }
        ) # this sends to slack and logs too
      end

      sig { params(team: EnterpriseTeam, assignment: Copilot::SeatAssignment).void }
      def refresh_seat_assignment(team, assignment)
        GitHub.logger.info("Refreshing SeatAssignment for Enterprise Team")
        tell_slack("Refreshing SeatAssignment For EnterpriseTeam #{team.id}-#{team.slug}")

        # If we got here, the date must exist
        old_pending_cancellation_date = assignment.pending_cancellation_date
        # We have to do this as assigning_user is nilable
        assigning_user = assignment.assigning_user || T.must(team.business).owners.first

        with_write do
          assignment.pending_cancellation_date = nil
          assignment.save!
        end

        Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_refreshed(
          assignment,
          assigning_user,
          pending_cancellation_date_was: old_pending_cancellation_date.iso8601,
        )
      end
    end
  end
end
