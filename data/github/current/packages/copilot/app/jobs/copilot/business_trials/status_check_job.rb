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
        with_write do
          Copilot::BusinessTrial.active.find_each do |trial|
            trial.check_status!
          end
        end
      end
    end
  end
end
