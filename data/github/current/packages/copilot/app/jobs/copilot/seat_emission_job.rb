# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 3.hours, condition: -> { GitHub.copilot_for_business_enabled? }
    gate_with_feature_flag :copilot_seat_emission_job
    exempt_from_tenant_context_requirement

    # For seat emissions, we are going to have two kinds of organizations that need to be billed:

    # 1. Standalone organizations (with no business associated)
    # 2. Organizations with a business associated

    # For the former, we can just add up the seats and emit for usage

    # For the latter, it gets a bit more complicated.  A user might be a member (and have a seat) in multiple organizations within the enterprise. We can only bill them once per enterprise.
    # To do that, we need to get all of the {organization, user_id} tuples for the enterprise and then remove any duplicates.

    # Assume we have Org A and Org B.  If User 1 is a member of both Org A and Org B and has a seat in both orgs, we only want to bill them for one seat.
    sig { void }
    def perform
      GitHub.logger.info("Starting Copilot seat emission job", "code.function" => "perform")
      GitHub.logger.info("Loading businesses and organizations for emission")

      @entity_ids      = T.let(org_and_biz_ids_through_seats, T.nilable(T::Hash[Symbol, T::Array[Integer]]))
      business_ids     = T.must(@entity_ids).fetch(:business_ids, [])
      organization_ids = T.must(@entity_ids).fetch(:organization_ids, [])

      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.seat_emission.businesses_count" => business_ids.count, "gh.copilot.seat_emission.organizations_count" => organization_ids.count) do
        GitHub.logger.info("Processing businesses")
        business_ids.each do |business_id|
          GitHub.logger.info("Processing business", "gh.copilot.seat_emission.business_id" => business_id)
          Copilot::Billing::EnterpriseSeatEmissionJob.perform_later(business_id)
        end

        GitHub.logger.info("Processing organizations")
        organization_ids.each do |organization_id|
          GitHub.logger.info("Processing organization", "gh.copilot.seat_emission.organization_id" => organization_id)
          Copilot::Billing::OrganizationSeatEmissionJob.perform_later(organization_id)
        end

        Copilot::SeatAssignment.where(assignable_type: "EnterpriseTeam").group(:owner_id).pluck(:owner_id).each do |owner_id|
          GitHub.logger.info("Processing enterprise team", "gh.copilot.seat_emission.business_id" => owner_id)
          Copilot::Billing::EnterpriseTeamEmissionJob.perform_later(owner_id)
        end
      end
    end
  end
end
