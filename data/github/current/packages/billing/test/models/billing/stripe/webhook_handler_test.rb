# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::WebhookHandlerTestCase < GitHub::BillingTestCase
  def build_payload(event_name)
    JSON.parse(
      File.read(
        Rails.root.join("test", "fixtures", "billing", "stripe", "events", "#{event_name}.json"),
      ),
    )
  end

  def build_signature_with(payload, secret = @secret)
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, secret)

    "t=#{timestamp.to_i},v1=#{signature}"
  end

  setup do
    @payout_created = build_payload("payout_created")
    @charge_succeeded = build_payload("charge_succeeded")
    @secret = "secret1"
    @source = :connect
  end

  context ".handle" do
    test "throws invalid signature error when no signature provided" do
      assert_raises Billing::Stripe::WebhookHandler::InvalidSignature do
        Billing::Stripe::WebhookHandler.handle(
          payload: @payout_created.to_json,
          signature: nil,
          secret: @secret,
          source: @source,
        )
      end
    end

    test "throws invalid signature error when no secret setup" do
      assert_raises Billing::Stripe::WebhookHandler::InvalidSignature do
        Billing::Stripe::WebhookHandler.handle(
          payload: @payout_created.to_json,
          signature: "signature",
          secret: nil,
          source: @source,
        )
      end
    end

    test "increments stripe webhook failed error count on failure" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      begin
        Billing::Stripe::WebhookHandler.handle(
          payload: @payout_created.to_json,
          signature: "signature",
          secret: nil,
          source: @source,
        )
      rescue Billing::Stripe::WebhookHandler::InvalidSignature
        increments = GitHub.dogstats.increments("stripe.webhook.signature_verification_error",
          tags: ["source:connect"]
        )

        assert_equal 1, increments.count
      end
    end

    test "increments stripe webhook count" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      signature = build_signature_with(@payout_created.to_json)

      Billing::Stripe::WebhookHandler.handle(
        payload: @payout_created.to_json,
        signature: signature,
        secret: @secret,
        source: @source,
      )

      increments = GitHub.dogstats.increments("stripe.webhook",
        tags: ["kind:payout_created", "source:connect"]
      )

      assert_equal 1, increments.count
    end

    test "persists webhook payload information" do
      signature = build_signature_with(@payout_created.to_json)

      assert_difference(-> { ::Billing::StripeWebhook.count }, 1) do
        Billing::Stripe::WebhookHandler.handle(
          payload: @payout_created.to_json,
          signature: signature,
          secret: @secret,
          source: @source,
        )
      end

      created_stripe_webhook = ::Billing::StripeWebhook.last
      created_stripe_webhook = T.must(created_stripe_webhook)
      assert_equal Billing::Stripe::WebhookHandler.fingerprint_for(@payout_created.to_json, @secret),
        created_stripe_webhook.fingerprint
      assert_equal "payout_created", created_stripe_webhook.kind
      assert_equal "pending", created_stripe_webhook.status
      assert_equal @payout_created, created_stripe_webhook.payload
    end

    test "enqueues a job to process the webhook immediately" do
      signature = build_signature_with(@payout_created.to_json)

      assert_enqueued_with(job: StripeWebhookJob) do
        Billing::Stripe::WebhookHandler.handle(
          payload: @payout_created.to_json,
          signature: signature,
          secret: @secret,
          source: @source,
        )
      end
    end
  end
end
