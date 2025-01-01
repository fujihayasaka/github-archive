# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module AuthAndCapture
    class AuthorizeTrialJob < BillingJob
      queue_as :authorize_ghec_trials
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      resolve_tenant_context do |trial|
        trial
      end

      sig { params(trial: Business, actor: User).returns(T.untyped) }
      def perform(trial, actor)
        copilot_business = ::Copilot::Business.new(trial)
        billable = copilot_business.copilot_billable?

        if trial.eligible_for_dfd_authorization?
          valid_azure_subscription = trial.has_valid_azure_subscription?

          # Do nothing if DFD authorization already in progress and trial doesn't have a valid Azure subscription.
          return if trial.dfd_authorization_in_progress? && !valid_azure_subscription

          # Set result to true if trial has a valid Azure subscription, otherwise run DFD authorization.
          result = valid_azure_subscription ? true : trial.run_dfd_trial_authorization

          # Ensure tenant context is set as it tends to get removed after the
          # Billing::CreateAuthorizationBillingTransactionJob is performed on running DFD authorization.
          GitHub::CurrentTenant.set(trial) if GitHub.multi_tenant_enterprise?

          if result
            with_write do
              copilot_business.create_or_resume_copilot_business_trials(
                actor,
                skip_billable_check_on_trial_creation: true
              )
            end

            instrument_trial_authorization(trial, true, billable)
          else
            DigitalFrontDoorMailer.authorization_failed(trial).deliver_later
            instrument_trial_authorization(trial, false, false)
          end
        else
          instrument_trial_authorization(trial, false, false)
        end
      end

      private

      sig { params(trial: Business, success: T::Boolean, billable: T::Boolean).returns(T.untyped) }
      def instrument_trial_authorization(trial, success, billable)
        GlobalInstrumenter.instrument(
          "billing.authorize_ghec_trial", {
            enterprise: trial,
            authorization_successful: success,
            is_billable: billable,
            expiration_date: trial.trial_expires_at,
          }
        )
      end
    end
  end
end
