# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class ExpirationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_business_trial_job

      resolve_tenant_context do |organization_id|
        ::Organization.find_by(id: organization_id)&.business
      end

      sig { params(organization_id: Integer).void }
      def perform(organization_id)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.org.id" => organization_id,
        ) do
          organization = ::Organization.find(organization_id)
          business_trial = Copilot::Organization.new(organization).business_trial
          return if business_trial.nil?

          unless business_trial.expired? || business_trial.canceled?
            GitHub.logger.info("Business trial is not expired or canceled - skipping job", "gh.copilot.business_trial.state" => business_trial.state, "gh.org.id" => organization_id)
            return
          end

          if business_trial.copilot_plan_business?
            if FeatureFlag.vexi.enabled?(:copilot_business_trial_remove_seat_assignments_on_expiration, organization, default: false)
              seat_assignments = Copilot::SeatAssignment.where(organization_id: organization.id)
              seats = Copilot::Seat.where(organization_id: organization.id)
              removed = 0

              with_write do
                GitHub.logger.info(
                  "Removing Copilot seat assignments for trial organization",
                )
                begin
                  Copilot::Seat.throttle_writes do
                    seats.each do |seat|
                      seat.cancel!(trial_seat: true, reason: :trial_expired)
                      removed += 1
                    rescue => error
                      GitHub.logger.info("Failed to cancel seat", "gh.copilot.seat.id" => seat.id, "gh.error.message" => error.message)
                      next
                    end
                  end

                  Copilot::SeatAssignment.throttle_writes do
                    seat_assignments.destroy_all
                  end

                  GitHub.dogstats.increment("copilot.business_trials.expiration_job.removed_seat_assignments")
                  GitHub.logger.info(
                    "Removed Copilot seat assignments for trial organization",
                    "gh.copilot.trial.assignment_count" => seat_assignments.count,
                    "gh.copilot.trial.seat_count_removed" => removed,
                  )
                rescue => error
                  handle_copilot_error(
                    Copilot::Errors::SeatAssignmentError.new("Failed to remove seat assignments on trial expiration"),
                    { "gh.org.id" => organization_id, "gh.error.message" => error.message }
                  )

                  # Raise so the job fails and can be retried
                  raise error
                end
              end
            else
              seat_assignments = Copilot::SeatAssignment.where(organization_id: organization.id)
              with_write do
                seat_assignments.update_all(pending_cancellation_date: Date.current)
              end
              GitHub.dogstats.increment("copilot.business_trials.expiration_job.cancelled_seat_assignments")
              seat_assignments.each do |seat_assignment|
                GitHub.dogstats.distribution_time("copilot.business_trials.expiration_job.duration") do
                  GitHub.logger.info("Kicking off SeatAssignmentCleanupJob", "gh.copilot.seat_assignment.id" => seat_assignment.id)
                  Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(seat_assignment.id, trial_seats: true)
                end
              end
            end

            business = organization.business

            if business
              copilot_business = Copilot::Business.new(business)
              GitHub.dogstats.distribution_time("copilot.business_trials.expiration_job.duration") do
                if Copilot::Seat.where(organization_id: business.organization_ids - [organization_id]).any?
                  GitHub.logger.info("Disabling Copilot for trial organization", "gh.org.id" => organization_id)
                  copilot_business.disable_copilot_for_selected_organizations!([organization_id])
                else
                  GitHub.logger.info("Disabling Copilot for business", "gh.business.id" => business.id)
                  copilot_business.disable_copilot!
                end
              end
            else
              # Standalone orgs
              copilot_organization = Copilot::Organization.new(organization)
              if business_trial.trialable_is_copilot_billable?
                Copilot::Organization.new(organization).seat_management_disable!
              else
                GitHub.logger.info("Disabling Copilot for trial organization", "gh.org.id" => organization.id)
                copilot_organization.disable_copilot!
              end
            end
          elsif business_trial.copilot_plan_enterprise?
            business_trial.process_disabling_copilot_enterprise_features
          end

          Copilot::Instrumenter.instrument_copilot_business_trial_ended(organization)
        end
      end
    end
  end
end
