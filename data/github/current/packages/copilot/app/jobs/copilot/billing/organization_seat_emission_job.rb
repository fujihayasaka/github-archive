# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class OrganizationSeatEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      # We don't want to allow multiple versions of this job to run for the same organization, even if they have
      # different already_billed_user_ids.
      locked_by timeout: 5.minutes, key: ->(job) do
        organization_id = job.arguments[0]
        DEFAULT_LOCK_STRINGIFY_PROC.call([organization_id])
      end

      gate_with_feature_flag :copilot_seat_emission_job

      resolve_tenant_context do |organization_id|
        ::Organization.find(organization_id).business
      end

      # This job is idempotent per day - no matter how many times it runs within the same 24 hours, it will only emit
      # one emission to Meuse per organization.
      sig { params(organization_id: Integer, already_billed_user_ids: T::Set[Integer]).void }
      def perform(organization_id, already_billed_user_ids: Set.new)
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.org.id" => organization_id,
          "gh.copilot.seat_emission.already_billed_user_ids" => already_billed_user_ids,
        ) do
          organization = ::Organization.find_by(id: organization_id)

          unless organization
            GitHub.logger.info("Organization not found")

            Copilot::ErrorReporter.report!(
              Copilot::Errors::SeatEmissionOrganizationMissingError.new("No organization found"),
              extra_details: {
                "gh.organization.id" => organization_id,
                "gh.copilot.already_billed_user_ids" => already_billed_user_ids,
              },
            )
            return
          end

          GitHub.logger.info(
            "Running SeatEmission Command",
            "gh.org.id" => organization_id,
            "gh.org.login" => organization.login,
            "gh.business.id" => organization.business.try(:id),
          )
          Copilot::Billing::OrganizationSeatEmissionCommand.call(organization, already_billed_user_ids: already_billed_user_ids)
        end
      end
    end
  end
end
