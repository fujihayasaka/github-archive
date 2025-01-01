# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class CleanupNonEmittingOrgsJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 24.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_seat_emission_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        GitHub.logger.with_named_tags("code.namespace" => self.class.name, "code.function" => "perform") do
          GitHub.dogstats.distribution_time("copilot.billing.cleanup_non_emitting_orgs_job.duration") do
            GitHub.logger.info("Finding non-emitting orgs")

            non_emitting_org_ids.each do |org_id|
              GitHub.logger.info("Non-emitting org found. Passing to OrganizationSeatEmissionJob", "gh.org.id" => org_id)
              Copilot::Billing::OrganizationSeatEmissionJob.perform_later(org_id)
            end
          end
        end
      end

      private

      sig { returns(T::Array[Integer]) }
      def non_emitting_org_ids
        # Load up all of the organizations that have a seat and are NOT a CFB trial
        non_trial_organization_ids = Copilot::Seat
          .where.not(organization_id: Copilot::BusinessTrial.active.pluck(:trialable_id))
          .group(:organization_id)
          .pluck(:organization_id)

        GitHub.dogstats.gauge("copilot.non_trial_organization_ids", non_trial_organization_ids.count)

        # find all of the seat emissions for these non-trial organizations that occurred in last 48 hours
        today = Date.current
        yesterday = Date.yesterday

        emitting_org_ids = Copilot::SeatEmission
          .where(owner_type: "Organization", owner_id: non_trial_organization_ids)
          .where(occurred_at: yesterday.beginning_of_day..today.end_of_day)
          .group(:owner_id)
          .pluck(:owner_id)

        GitHub.dogstats.gauge("copilot.emitting_org_ids", emitting_org_ids.count)

        non_emitting_orgs = non_trial_organization_ids - emitting_org_ids

        GitHub.dogstats.gauge("copilot.non_emitting_org_ids", non_emitting_orgs.count)

        non_emitting_orgs
      rescue StandardError => ex # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::CopilotError.from_error(ex))
        []
      end
    end
  end
end
