# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class UserJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers
      gate_with_feature_flag :copilot_seat_assignment_job

      resolve_tenant_context do |args|
        ::User.find_by(id: args[:user_id])&.enterprise_managed_business
      end

      sig do
        params(
          user_id: Integer,
          transaction_id: T.nilable(String),
          action: Symbol,
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
          clean_records: T::Boolean
        ).void
      end
      def perform(user_id:, transaction_id: nil, action: :destroy, payload: nil, actor_id: nil, clean_records: false)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.copilot.job_action" => action,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.user.id" => user_id,
        ) do
          @user_id         = T.let(user_id, T.nilable(Integer))
          @action          = T.let(action, T.nilable(Symbol))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))
          @clean_records   = T.let(clean_records, T.nilable(T::Boolean))

          raise ArgumentError, "Invalid action: #{action}" unless action == :destroy

          seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: @user_id)

          if seats.count > 0
            GitHub.logger.info(
              "Loaded Copilot Seats for user",
              "gh.copilot.seats.count" => seats.count,
              "gh.copilot.organization_ids" => seats.map(&:owner_id).join(","),
            )
          else
            GitHub.logger.info("No Copilot Seats Found for user")
          end

          # This array will contain the seat assignment ids we found and processed.
          # Note that they may be deleted in the process of this job. We still want to
          # capture them so we don't try to destroy them again later.
          found_seat_assignment_ids = []

          # Because a user could have multiple seats in organizations that both have
          # revokable access and don't, we need to keep track of the seat ids we will destroy.
          seats_ids_to_destroy = []
          assignment_ids_to_destroy = []

          seats.each do |seat|
            # get seat assignment, disassociate if not user assignment and revoke access
            seat_assignment = seat.seat_assignment

            if seat_assignment.nil?
              # we didn't find a seat_assignment for the seat, this is unlikely but let's tell someone
              # we don't need to clean this seat up because the DeleteOrphanedSeatJob will get it
              report_error("Seat assignment not found for seat #{seat.id}")
              next
            end

            if seat_assignment.copilot_owner.feature_enabled?(:copilot_revokable_access)
              found_seat_assignment_ids << with_write { revoke_seat_assignment_access(seat) }
            else
              seats_ids_to_destroy << seat.id
              if seat_assignment.assignable_type == "User"
                assignment_ids_to_destroy << seat_assignment.id
              end
            end
          end

          # Any seat associated with an owner not enrolled in the revokable access feature flag should be destroyed.
          destroy_user_seats_and_assignments(
            Copilot::Seat.where(id: seats_ids_to_destroy),
            assignment_ids_to_destroy
          ) if seats_ids_to_destroy.count > 0

          # Destroy any other random user seat assignments that don't have seats just in case.
          # Passing the found_seat_assignment_ids to the where clause will ensure we only destroy
          # seat assignments we have not already destroyed.
          # in the above call, when removing seats belonging to owners that don't have revokable access.
          assignments_to_destroy = Copilot::SeatAssignment
            .where(assignable_type: "User", assignable_id: @user_id)
            .where.not(id: found_seat_assignment_ids)

          if assignments_to_destroy.count > 0
            GitHub.logger.info(
              "Destroying User Seat Assignments for user which were not linked to seats",
              "gh.user.id" => @user_id,
              "gh.copilot.seat_assignment.ids" => assignments_to_destroy.pluck(:id).join(","),
            )
            with_write do
              assignments_to_destroy.destroy_all
            end
            GitHub.dogstats.count("copilot.seat_management.user_job.orphaned_assignments_destroyed", assignments_to_destroy.count)
          else
            GitHub.logger.info("No User Seat Assignments for user which were not linked to seats")
          end

          with_write do
            destroy_associated_copilot_records(@user_id, seats_ids_to_destroy)
          end if @clean_records && @user_id.present?
        end
      end

      sig { params(seat: Copilot::Seat).returns(Integer) }
      def revoke_seat_assignment_access(seat)
        seat_assignment = T.must(seat.seat_assignment)

        if seat_assignment.assignable_type == "User"
          GitHub.logger.info(
            "Unassigning and revoking access for user seat assignment",
            "gh.copilot.seat.id" => seat.id,
            "gh.copilot.seat_assignment.id" => seat_assignment.id,
            "gh.copilot.owner_id" => seat_assignment.owner_id,
            "gh.copilot.owner_type" => seat_assignment.owner_type,
          )

          seat_assignment.unassign_and_revoke_access!(nil, :user_destroyed)
          GitHub.dogstats.increment("copilot.seat_management.user_job.access_revoked", tags: ["owner:#{seat_assignment.owner_type.downcase}"])

          seat_assignment.id
        else
          # we found a non-user seat assignment, we need to disassociate it and revoke access from it
          disassociated_seat_assignment = create_disassociated_seat_assignment(T.must(@user_id), seat, seat_assignment, :user_removed_from_team, nil)
          GitHub.dogstats.increment("copilot.seat_management.user_job.assignment_disassociated", tags: ["owner:#{seat_assignment.owner_type.downcase}"])

          GitHub.logger.info(
            "Unassigning and revoking access for disassociated seat assignment",
            "gh.copilot.seat.id" => seat.id,
            "gh.copilot.seat_assignment.id" => disassociated_seat_assignment.id,
            "gh.copilot.owner_id" => disassociated_seat_assignment.owner_id,
            "gh.copilot.owner_type" => disassociated_seat_assignment.owner_type,
          )
          # unassigning_user can be nil here because it's mostly for audit logging and GitHub System will be doing this
          disassociated_seat_assignment.unassign_and_revoke_access!(nil, :user_destroyed)

          # repoint to the disassociated seat assignment
          seat.update_column(:copilot_seat_assignment_id, disassociated_seat_assignment.id)
          GitHub.dogstats.increment("copilot.seat_management.user_job.access_revoked", tags: ["owner:#{seat_assignment.owner_type.downcase}"])

          disassociated_seat_assignment.id
        end
      end

      sig { params(seats: ActiveRecord::Relation, assignment_ids: T::Array[Integer]).void }
      def destroy_user_seats_and_assignments(seats, assignment_ids)
        GitHub.logger.info("Destroying Copilot Seats for user", "gh.copilot.seats.count" => seats.count)
        with_write do
          seats.destroy_all # need to call this because the notifications won't work - there is no user any more (pour one out)
        end
        GitHub.dogstats.count("copilot.seat_management.user_job.seats_destroyed", seats.count)

        seat_assignments = Copilot::SeatAssignment.where(id: assignment_ids)

        if seat_assignments.count > 0
          GitHub.logger.info(
            "Destroying User Level Copilot Seat Assignments for user",
            "gh.copilot.seat_assignments.count" => seat_assignments.count,
            "gh.copilot.organization.ids" => seat_assignments.map(&:organization_id).join(","),
          )
          with_write do
            seat_assignments.destroy_all
          end
          GitHub.dogstats.count("copilot.seat_management.user_job.user_seat_assignments_destroyed", seat_assignments.count)
        else
          GitHub.logger.info("No User Level Copilot Seat Assignments for user")
        end
      end

      sig { params(message: String).void }
      def report_error(message)
        details = {
          :action => @action,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
          "gh.actor.id" => @actor_id,
        }
        handle_error(message, details)
      end

      sig { params(user_id: Integer, seat_ids: T::Array[Integer]).void }
      def destroy_associated_copilot_records(user_id, seat_ids)
        GitHub.logger.info("Destroying associated Copilot records for user, if any exist", "gh.user.id" => user_id)

        deleted_copilot_activities = Copilot::Activity.where(copilot_seat_id: seat_ids).destroy_all
        GitHub.logger.info("Destroyed copilot activities", "gh.copilot.activities.count" => deleted_copilot_activities.count)

        deleted_copilot_activity_histories = Copilot::ActivityHistory.where(copilot_seat_id: seat_ids).destroy_all
        GitHub.logger.info("Destroyed copilot activity histories", "gh.copilot.activity_histories.count" => deleted_copilot_activity_histories.count)

        deleted_copilot_authentications = Copilot::Authentication.where(copilot_seat_id: seat_ids).destroy_all
        GitHub.logger.info("Destroyed copilot authentications", "gh.copilot.authentications.count" => deleted_copilot_authentications.count)

        deleted_copilot_authentication_histories = Copilot::AuthenticationHistory.where(copilot_seat_id: seat_ids).destroy_all
        GitHub.logger.info("Destroyed copilot authentication histories", "gh.copilot.authentication_histories.count" => deleted_copilot_authentication_histories.count)

        deleted_configurations = Copilot::Configuration.where(configurable_type: "User", configurable_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed configurations",
          "gh.copilot.configurations.count" => deleted_configurations.count
        ) if deleted_configurations.count > 0

        deleted_free_users = Copilot::FreeUser.where(user_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed free users",
          "gh.copilot.free_users.count" => deleted_free_users.count
        ) if deleted_free_users.count > 0

        deleted_limited_users = Copilot::LimitedUser.where(user_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed limited users",
          "gh.copilot.limited_users.count" => deleted_limited_users.count
        ) if deleted_limited_users.count > 0

        deleted_notifications = Copilot::EditorNotification.where(user_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed editor notifications",
          "gh.copilot.editor_notifications.count" => deleted_notifications.count
        ) if deleted_notifications.count > 0

        deleted_details = Copilot::AggregateUsageDetail.where(user_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed aggregate usage details",
          "gh.copilot.aggregate_usage_details.count" => deleted_details.count
        ) if deleted_details.count > 0

        deleted_technical_preview_users = Copilot::TechnicalPreviewUser.where(user_id: @user_id).destroy_all
        GitHub.logger.info(
          "Destroyed technical preview users",
          "gh.copilot.technical_preview_users.count" => deleted_technical_preview_users.count
        ) if deleted_technical_preview_users.count > 0
      end
    end
  end
end
