# typed: strict
# frozen_string_literal: true

module Copilot
  module BusinessTrials
    class StatusCheckJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 6.hours, condition: -> { GitHub.copilot_for_business_enabled? }
      gate_with_feature_flag :copilot_business_trial_job
      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        Copilot::BusinessTrial.active.find_each do |trial|
          with_write do
            trial.check_status!
          rescue => e # rubocop:disable Lint/GenericRescue
            Failbot.report(e, {
              "code.namespace" => self.class.name,
              "code.function" => "perform",
              "gh.copilot.business_trial.id" => trial.id,
              "gh.message" => "Error checking / updating business trial status",
              "gh.caller" => caller.to_s
            })
          end
        end
      end
    end
  end
end
