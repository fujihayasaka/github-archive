# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class ExpirationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_business_trial_job

      sig { params(organization_id: Integer).void }
      def perform(organization_id)
        GitHub.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => "perform") do
          organization = ::Organization.find(organization_id)
          business_trial = Copilot::Organization.new(organization).business_trial
          return if business_trial.nil?

          if business_trial.copilot_plan_business?
            seat_assignments = Copilot::SeatAssignment.where(organization_id: organization.id)
            with_write do
              seat_assignments.update_all(pending_cancellation_date: Date.current)
            end
            seat_assignments.each do |seat_assignment|
              GitHub.dogstats.distribution_time("copilot.business_trials.expiration_job.duration") do
                GitHub.logger.info("Kicking off SeatAssignmentCleanupJob", "gh.copilot.seat_assignment.id" => seat_assignment.id)
                Copilot::SeatManagement::SeatAssignmentCleanupJob.perform_later(seat_assignment.id, trial_seats: true)
              end
            end

            business = organization.business

            if business
              copilot_business = Copilot::Business.new(business)
              GitHub.dogstats.distribution_time("copilot.business_trials.expiration_job.duration") do
                if Copilot::Seat.where(organization_id: business.organization_ids - [organization_id]).any?
                  GitHub.logger.info("Disabling Copilot for trial organization", "gh.organization.id" => organization_id)
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
                GitHub.logger.info("Disabling Copilot for trial organization", "gh.organization.id" => organization.id)
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
