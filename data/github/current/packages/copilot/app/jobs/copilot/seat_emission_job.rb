# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: FeatureFlag.vexi.enabled?(:copilot_seat_emission_job_scheduled, default: false) ? 1.hour : 3.hours, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_emission_job
    exempt_from_tenant_context_requirement

    # For seat emissions, we are going to have two kinds of organizations that need to be billed:

    # 1. Standalone organizations (with no business associated)
    # 2. Organizations with a business associated

    # For the former, we can just add up the seats and emit for usage

    # For the latter, it gets a bit more complicated.  A user might be a member (and have a seat) in multiple organizations within the enterprise. We can only bill them once per enterprise.
    # To do that, we need to get all of the {organization, user_id} tuples for the enterprise and then remove any duplicates.

    # Assume we have Org A and Org B.  If User 1 is a member of both Org A and Org B and has a seat in both orgs, we only want to bill them for one seat.
    #
    # Additionally, we have to bill for standalone enterprises, and enterprises that have either individual user licenses, or control revoked seat assignments
    # from former child organizations.
    sig { void }
    def perform
      if FeatureFlag.vexi.enabled?(:copilot_seat_emission_job_scheduled, default: false)
        # return early unless this job is running every 3 hours but not in the last hour of the day (23) utc
        # this is to avoid running the job in the last hour of the day utc, which
        # is when the pending seat assignments job runs and we don't want to emit seats
        last_run_hour = Copilot::PendingSeatAssignmentsJob::DAILY_RUN_HOUR - 1
        run_hours = (1..last_run_hour).step(3).to_a
        # [1, 4, 7, 10, 13, 16, 19, 22]
        unless run_hours.include?(Time.current.utc.hour)
          GitHub.logger.info("Skipping Copilot::SeatEmissionJob because it's not the right time to run", "gh.seat_emission_job_run_hours" => run_hours)
          return
        end
      end
      GitHub.logger.info("Starting Copilot seat emission job", "code.function" => "perform")
      GitHub.logger.info("Loading businesses and organizations for emission")

      @entity_ids      = T.let(org_and_biz_ids_through_seats, T.nilable(T::Hash[Symbol, T::Array[Integer]]))
      business_ids     = T.must(@entity_ids).fetch(:business_ids, [])

      # independent meaning there's no associated enterprise
      independent_org_ids = T.must(@entity_ids).fetch(:independent_org_ids, [])

      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.seat_emission.businesses_count" => business_ids.count, "gh.copilot.seat_emission.organizations_count" => independent_org_ids.count) do
        GitHub.logger.info("Processing businesses")
        business_ids.each do |business_id|
          GitHub.logger.info("Processing business", "gh.copilot.seat_emission.business_id" => business_id)
          Copilot::Billing::EnterpriseSeatEmissionJob.perform_later(business_id)
        end

        # this calls the emission job for organizations that are NOT part of an enterprise
        GitHub.logger.info("Processing organizations")
        independent_org_ids.each do |organization_id|
          GitHub.logger.info("Processing organization", "gh.copilot.seat_emission.organization_id" => organization_id)
          Copilot::Billing::OrganizationSeatEmissionJob.perform_later(organization_id)
        end
      end
    end
  end
end
