# typed: true
# frozen_string_literal: true

module Billing
  class CheckPaymentMethodUniqueNumberIdentifierReuseOverThresholdJob < BillingJob
    queue_as :billing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    exempt_from_tenant_context_requirement

    def perform
      payment_methods_with_reused_fingerprints_over_threshold = PaymentMethod.with_card_fingerprint_reuse_over_threshold_in_last_30_days

      GitHub.dogstats.gauge("billing.payment_methods_with_reused_fingerprints_over_threshold.count", payment_methods_with_reused_fingerprints_over_threshold.count)
    end
  end
end
