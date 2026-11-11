# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotCheckRunFailureContext < Platform::Objects::Base
      description "The context of a Copilot check run failure."

      required_capabilities [:mobile_only_schema_mask]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(:read_check_run, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_check_suite.then do |check_suite|
          permission.typed_can_see?("CheckSuite", check_suite)
        end
      end

      def initialize(job_id:)
        @job_id = job_id
      end

      field :job_id, Scalars::BigInt, null: false, description: "The job id of the failed check run."

      def job_id
        @job_id
      end
    end
  end
end
