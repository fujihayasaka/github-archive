# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module StripeWebhook
    class TransferFailed
      extend T::Sig

      # Public: Handle the transfer failed webhook payload
      sig { params(webhook: Billing::StripeWebhook).void }
      def self.perform(webhook)
        new(webhook).perform
      end

      # Public: Initializes a new TransferFailed webhook handler
      sig { params(webhook: Billing::StripeWebhook).void }
      def initialize(webhook)
        @webhook = webhook
      end

      # Public: Handle the transfer failed webhook payload
      sig { void }
      def perform
        GitHub.dogstats.increment("stripe.transfer_failed")
      end
    end
  end
end
