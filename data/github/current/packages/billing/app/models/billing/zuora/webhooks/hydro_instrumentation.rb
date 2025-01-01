# typed: strict
# frozen_string_literal: true

# Common methods for Hydro instrumentation in Zuora webhooks
module Billing::Zuora::Webhooks::HydroInstrumentation
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ::Billing::Zuora::Webhooks::WebhookHandler }

  # Internal: Instrument the payment transaction so that it can be logged
  # in Hydro to github_billing_v0_payment_transaction, and adds an audit log for easier
  # support debugging.
  #
  # success - Whether or not this transaction was successful
  # trial_completion_status_before_processing - business.trial_completion_status before the job has run
  # trial_completion_status_after_processing - business.trial_completion_status after the job has run
  sig do
    params(
      success: T::Boolean,
      trial_completion_status_before_processing: T.nilable(String),
      trial_completion_status_after_processing: T.nilable(String)
    ).void
  end
  def instrument_payment_transaction(success:, trial_completion_status_before_processing: nil, trial_completion_status_after_processing: nil)
    account = self.account

    payment_information = {
      payment_method_id: payment_method&.id,
      payment_amount: zuora_payment.amount_in_cents,
      attempt_number: zuora_payment.num_consecutive_failures + 1,
      processor_response_code: zuora_payment.processor_response_code,
      processor_response: zuora_payment.processor_response,
    }

    payload = {
      user_id: account.is_a?(::User) ? account.id : nil,
      business_id: account.is_a?(::Business) ? account.id : nil,
      success: success,
    }.merge(payment_information)
    # hydro github_billing_v0_payment_transaction
    GlobalInstrumenter.instrument("billing.payment_transaction", payload)

    # Audit Logs
    audit_log_payload = {}
    if account.is_a?(::User)
      audit_log_payload = payment_information.merge({
        user_id: account.id,
        user: account.display_login
      })
    end
    if account.is_a?(::Business)
      audit_log_payload = payment_information.merge({
        business_id: account.id,
        business: account.display_login,
        trial_completion_status_before_processing: trial_completion_status_before_processing,
        trial_completion_status_after_processing: trial_completion_status_after_processing,
      })
    end
    event = success ? "billing.payment_processed" : "billing.payment_declined"
    GitHub.instrument event, audit_log_payload
  end
end
