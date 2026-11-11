# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrganizationRemoveMemberJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers
      include Copilot::SeatManagement::SeatAssignmentHelpers

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_assignment_job

      resolve_tenant_context do |data|
        organization = ::Organization.find_by(id: data[:organization_id])
        organization&.business
      end

      sig do
        params(
          user_id: Integer,
          organization_id: Integer,
          transaction_id: T.nilable(String),
          invitation_email: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, T.untyped]), # rubocop:disable Sorbet/ForbidTUntyped
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(user_id:, organization_id:, transaction_id: nil, invitation_email: nil, payload: nil, actor_id: nil)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.actor.id" => actor_id,
          "gh.instrumentation.transaction_id" => transaction_id,
          "gh.org.id" => organization_id,
          "gh.org.invitation.email" => invitation_email,
          "gh.user.id" => user_id,
        ) do
          @user_id         = T.let(user_id, T.nilable(Integer))
          @organization_id = T.let(organization_id, T.nilable(Integer))
          @transaction_id  = T.let(transaction_id, T.nilable(String))
          @payload         = T.let(payload, T.nilable(T::Hash[Symbol, T.untyped])) # rubocop:disable Sorbet/ForbidTUntyped
          @actor_id        = T.let(actor_id, T.nilable(Integer))
          @invitation_email = T.let(invitation_email, T.nilable(String))

          # load up the organization - this is required so if it isn't there, report an exception. We might want to tweak this later
          organization = ::Organization.find_by(id: organization_id)
          return report_error("User being removed from invalid or non-existant Organization") unless organization

          copilot_organization = Copilot::Organization.new(organization)
          unless copilot_organization.copilot_for_business_enabled?
            # why are we here?  what have we done with our lives that got us to this place right here?
            GitHub.logger.info("User being removed from org that doesn't have Copilot enabled, exiting")
            return
          end

          user = ::User.find_by(id: user_id)
          unless user
            # why?  just why?  what is happening?  we don't have a user but the user was added to the org or restored or something?
            GitHub.logger.error("User being removed from org is invalid or non-existant")
            Copilot::SeatManagement::UserJob.perform_now(user_id: user_id, clean_records: true)
            return
          end

          seats = Copilot::Seat.where(
            organization_id: @organization_id,
            assigned_user_id: @user_id
          )

          GitHub.dogstats.increment "copilot.organization_remove_member_job.member_removed",
            tags: ["seats:#{seats.any?}"]

          user_assignments_for_org = Copilot::SeatAssignment
            .for_organization(organization)
            .where(assignable_type: "User", assignable_id: user_id)

          if seats.empty? && user_assignments_for_org.empty?
            GitHub.logger.info("No seats or seat assignments to remove for user being removed from organization")
            return
          end

          actor = actor_id ? ::User.find_by(id: actor_id) : nil

          seats.each do |seat|
            seat_assignment = seat.seat_assignment

            if seat_assignment
              case assignable_type = seat_assignment.assignable_type
              when "User"
                with_write do
                  seat_assignment.unassign_and_revoke_access!(actor, :org_member_removed)
                end
              when "Team"
                with_write do
                  user_assignment = create_disassociated_seat_assignment(
                    seat.assigned_user.id,
                    seat,
                    seat_assignment,
                    :org_member_removed,
                    actor,
                  )
                  seat.update_column(:copilot_seat_assignment_id, user_assignment.id)
                  user_assignment.unassign_and_revoke_access!(actor, :org_member_removed)
                end

                # sometimes teams don't exist when we get here.
                team_members = seat_assignment.assignable.present? ? seat_assignment.assignable.members : []
                if team_members.empty? || team_members == [seat.assigned_user]
                  GitHub.logger.info(
                    "Deleting SeatAssignment for empty Team now that last member has been removed",
                    "gh.copilot.seat_assignment.id" => seat_assignment.id,
                  )
                  with_write do
                    seat_assignment.destroy!(actor: actor)
                  end
                else
                  GitHub.logger.info(
                    "Skipping non-empty Team SeatAssignment for member removed from organization",
                    "gh.copilot.seat_assignment.id" => seat_assignment.id,
                  )
                end
              when "Organization"
                with_write do
                  user_assignment = create_disassociated_seat_assignment(
                    seat.assigned_user.id,
                    seat,
                    seat_assignment,
                    :org_member_removed,
                      actor,
                  )
                  seat.update_column(:copilot_seat_assignment_id, user_assignment.id)
                  user_assignment.unassign_and_revoke_access!(actor, :org_member_removed)
                end
              else
                GitHub.logger.info(
                  "Skipping #{assignable_type} SeatAssignment for member removed from organization",
                  "gh.copilot.seat_assignment.id" => seat_assignment.id,
                )
              end
            end
          end

          # not sure how we'd end up in this state (could be a race condition), but if we get here
          # and we still have user seat assignments that don't have seats associated with them, destroy them
          # this won't include newly-created disassociated assignments
          user_assignments_for_org.each do |user_assignment|
            next unless user_assignment.seats.empty?

            GitHub.logger.info(
              "Deleting User SeatAssignment for member removed from organization",
              "gh.copilot.seat_assignment.id" => user_assignment.id,
            )
            with_write do
              user_assignment.destroy!(actor: actor)
            end
          end

          # update cache and emit billable customer change now that the user is no longer in the org
          copilot_user = Copilot::User.new(user)
          copilot_user.create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION, throttle: true)

          # checking access_revokable so we don't emit twice if the feature is disabled for testing purposes,
          # but we're removing the feature flag soon anyway
          if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, copilot_user.user_object, default: false)
            Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(copilot_user.user_object))
          end
        end
      end

      private

      sig { params(message: String).void }
      def report_error(message)
        details = {
          "gh.organization.id" => @organization_id,
          :transaction_id => @transaction_id,
          :payload => @payload,
          "gh.user.id" => @user_id,
        }
        handle_copilot_error(Copilot::Errors::SeatDestructionError.new(message), details)
      end
    end
  end
end
