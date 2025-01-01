# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module StripeWebhook
    class ChargeSucceeded
      extend T::Sig

      # Public: Handle the charge succeeded webhook payload
      #
      # webhook - The Billing::StripeWebhook to process
      #
      # Returns nothing
      sig { params(webhook: Billing::StripeWebhook).void }
      def self.perform(webhook)
        new(webhook).perform
      end

      # Public: Initializes a new ChargeSucceeded webhook handler
      #
      # webhook - The Billing::StripeWebhook to process
      sig { params(webhook: Billing::StripeWebhook).void }
      def initialize(webhook)
        @webhook = webhook
      end

      # Public: Handle the charge succeeded webhook payload
      #
      # Returns nothing
      sig { void }
      def perform
        # allow time for the billing system to process the charge
        LogSponsorshipStripeRadarRiskScoreJob.set(wait: 4.hours).perform_later(webhook)
      end

      private

      sig { returns Billing::StripeWebhook }
      attr_reader :webhook
    end
  end
end
