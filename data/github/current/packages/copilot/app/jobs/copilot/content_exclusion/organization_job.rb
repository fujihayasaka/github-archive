# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    class OrganizationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig
      include Copilot::Helpers

      VALID_ACTIONS = T.let(%i[
        organization_destroyed
      ], T::Array[Symbol])

      sig do
        params(
          organization_id: Integer,
          action: Symbol,
          transaction_id: T.nilable(String),
        ).void
      end
      def perform(organization_id:, action: :unknown, transaction_id: nil)
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
          GitHub.dogstats.distribution_time("copilot.content_exclusion.organization_job.duration") do
            GitHub.logger.info("Processing action #{action}")

            case action
            when :organization_destroyed
              deleted_entities = with_write do
                Copilot::ContentExclusionConfiguration.with_organization_ids([organization_id]).destroy_all
              end

              count = deleted_entities.count

              GitHub.dogstats.histogram("copilot.content_exclusion.destroy_rules", count)
              GitHub.logger.info("Organization destroyed so purged content exclusion configurations", {
                "gh.copilot.ignore.deleted.count": count,
              }) if count > 0
            end
          end
        end
      end
    end
  end
end
