# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module AuthAndCapture
    class AuthorizeTrialJob < BillingJob
      queue_as :authorize_ghec_trials
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      sig { params(trial: Business, actor: User).returns(T.untyped) }
      def perform(trial, actor)
        result = trial.run_trial_authorization
        if result
          GlobalInstrumenter.instrument(
            "billing.authorize_ghec_trial", {
              enterprise: trial,
              authorization_successful: true,
              expiration_date: trial.trial_expires_at,
            }
          )
          with_write { ::Copilot::Business.new(trial).create_or_resume_copilot_business_trials(actor) }
        else
          GlobalInstrumenter.instrument(
            "billing.authorize_ghec_trial", {
              enterprise: trial,
              authorization_successful: false,
              expiration_date: trial.trial_expires_at,
            }
          )
        end
      end
    end
  end
end
