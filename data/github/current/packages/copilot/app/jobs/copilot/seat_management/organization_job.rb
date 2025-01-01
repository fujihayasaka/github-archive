# typed: strict
# frozen_string_literal: true

module Copilot
  module SeatManagement
    class OrganizationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      include Copilot::Helpers

      gate_with_feature_flag :copilot_seat_assignment_job

      VALID_ACTIONS = T.let(%i[
        organization_archived
        organization_destroyed
        organization_suspended
        organization_destroying
      ], T::Array[Symbol])

      sig do
        params(
          organization_id: Integer,
          customer_id: T.nilable(Integer),
          action: Symbol,
          transaction_id: T.nilable(String),
          payload: T.nilable(T::Hash[Symbol, String]),
          actor_id: T.nilable(Integer),
        ).void
      end
      def perform(organization_id:, customer_id: nil, action: :unknown, transaction_id: nil, payload: nil, actor_id: nil)
        unless VALID_ACTIONS.include?(action)
          raise ArgumentError, "Invalid action: #{action}"
        end

        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.org.id" => organization_id,
          "gh.copilot.job_action" => action,
          "gh.transaction.id" => transaction_id,
        ) do
          GitHub.dogstats.distribution_time("copilot.seat_management.organization_job.duration") do
            GitHub.logger.info("Processing action #{action}")
            Copilot::OrganizationCleaner.call(organization_id, customer_id)

            Copilot::BatchUpdateUserSettingsJob.perform_later(organization_id)
          end
        end
      end
    end
  end
end
