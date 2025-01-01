# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class OrganizationAuthAndCaptureJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      gate_with_feature_flag :copilot_org_auth_and_capture_job

      resolve_tenant_context do |organization_id|
        ::Organization.find(organization_id).business
      end

      sig { params(organization_id: Integer, skip_previous_authorizations_check: T::Boolean, audit_log_reason: String, skip_account_age_check: T::Boolean).void }
      def perform(organization_id, skip_previous_authorizations_check: false, audit_log_reason: "unknown", skip_account_age_check: false)
        GitHub.logger.info("Attempting to get lock to start Copilot auth and capture job for organization #{organization_id}")
        # Only one job can run at a time for a given organization - if this instance fails to grab the lock, don't retry
        lock_key = organization_id.to_s
        concurrent_jobs = 1
        lock_ttl = 10.minutes
        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
          GitHub.logger.info("Starting Copilot auth and capture job for organization #{organization_id}")
          organization = ::Organization.find(organization_id)
          Copilot::Organization.new(organization).perform_auth_and_capture!(
            skip_account_age_check: skip_account_age_check,
            skip_previous_authorizations_check: skip_previous_authorizations_check,
            audit_log_reason: audit_log_reason,
          )
        end
      end
    end
  end
end
