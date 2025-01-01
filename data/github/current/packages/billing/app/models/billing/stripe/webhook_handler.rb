# typed: true
# frozen_string_literal: true

module Billing
  module Stripe
    class WebhookHandler
      InvalidSignature = Class.new(StandardError)

      # Public:  Generates a fingerprint for a stripe webhook payload and secret
      #
      # payload - Stripe webhook payload
      # secret - Stripe webhook secret
      #
      # Returns [String] generated fingerprint
      def self.fingerprint_for(payload, secret)
        OpenSSL::HMAC.hexdigest(
          OpenSSL::Digest.new("sha256"), secret, payload
        )
      end

      # Public: Instantiate a new handler by creating an incoming Stripe event
      # payload - Stripe webhook payload
      # signature - Stripe payload signature
      # source - Source of the Stripe webhook, used to determine secret to use signature verification
      # secret - Stripe webhook secret, defaults to inferring secret from source
      #
      # Returns [WebhookHandler] instance
      def self.handle(payload:, signature:, source:, secret: nil)
        secret ||= event_secret(source)
        new(
          webhook_event: ::Stripe::Webhook.construct_event(payload, signature, secret),
          fingerprint: fingerprint_for(payload, secret),
          source: source,
        ).handle
      rescue ::Stripe::SignatureVerificationError => e
        GitHub.dogstats.increment("stripe.webhook.signature_verification_error",
          tags: ["source:#{source}"]
        )
        raise InvalidSignature.new(e.message)
      end

      def initialize(webhook_event:, fingerprint:, source:)
        @webhook_event = webhook_event
        @fingerprint = fingerprint
        @source = source
      end

      # Internal: Determines the correct secret to use, depending on if this is
      # a webhook for a Connect account or our main Stripe account
      #
      # Returns string
      def self.event_secret(source)
        if source == :connect
          GitHub.stripe_connect_webhook_secret
        elsif source == :platform_general
          GitHub.stripe_v3_platform_webhook_secret
        else
          GitHub.stripe_platform_webhook_secret
        end
      end

      # Public: Handles an incoming Sripe webhook event
      #
      # Returns [WebhookHandler] instance
      def handle
        GitHub.dogstats.increment(
          "stripe.webhook",
          tags: [
            "kind:#{webhook_event_kind}",
            "source:#{source}",
          ],
        )

        webhook = StripeWebhook.create!(
          kind: webhook_event_kind,
          status: :pending,
          fingerprint: fingerprint,
          payload: webhook_event_payload,
        )
        StripeWebhookJob.perform_later(webhook)

        self
      end

      private

      attr_reader :webhook_event, :fingerprint, :source

      def webhook_event_payload
        webhook_event.as_json
      end

      def webhook_event_kind
        webhook_event_type.gsub(/\./, "_").to_sym # e.g., "payout.created" => :payout_created
      end

      def webhook_event_type
        webhook_event.type
      end
    end
  end
end
