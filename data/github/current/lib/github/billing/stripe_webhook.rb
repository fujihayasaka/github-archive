# typed: true
# frozen_string_literal: true

module GitHub
  module Billing
    module StripeWebhook
      autoload :AccountUpdated, "github/billing/stripe_webhook/account_updated"
      autoload :ChargeDispute, "github/billing/stripe_webhook/charge_dispute"
      autoload :PayoutCreated, "github/billing/stripe_webhook/payout_created"
      autoload :PayoutFailed, "github/billing/stripe_webhook/payout_failed"
      autoload :TransferCreated, "github/billing/stripe_webhook/transfer_created"
      autoload :TransferFailed, "github/billing/stripe_webhook/transfer_failed"
      autoload :TransferReversed, "github/billing/stripe_webhook/transfer_reversed"
      autoload :EarlyFraudWarning, "github/billing/stripe_webhook/early_fraud_warning"
      autoload :PaymentSucceeded, "github/billing/stripe_webhook/payment_succeeded"
      autoload :ChargeSucceeded, "github/billing/stripe_webhook/charge_succeeded"
      autoload :ChargeFailed, "github/billing/stripe_webhook/charge_failed"
    end
  end
end
