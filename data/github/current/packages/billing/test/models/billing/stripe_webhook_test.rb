# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class StripeWebhookTest < GitHub::TestCase
    context "#update_account_id_from_payload" do
      test "handles charge_dispute_created on deleted user" do
        stripe_webhook = build(:stripe_webhook, :charge_dispute_created)
        transaction_id = stripe_webhook.payload.dig("data", "object", "charge")
        billing_transaction = create(:billing_transaction, transaction_id: transaction_id)
        user = billing_transaction.user
        user.destroy
        stripe_webhook.save!
        assert_nil stripe_webhook.account_id
      end

      test "does not overwrite existing account_id when no account ID is present in the payload" do
        webhook = create(:stripe_webhook, :charge_succeeded)
        assert_nil webhook.account_id, "expected no account ID to be gleaned from the payload"

        webhook.account_id = "acct_123abc"
        webhook.save!

        assert_equal "acct_123abc", webhook.account_id, "expected account ID not to be overwritten"
      end
    end

    context "#set_user_id" do
      test "sets the user_id field based on billing_details.name when it's set to a numeric value and there's no account ID" do
        user = create(:user)
        stripe_webhook = Billing::StripeWebhook.new(
          payload: { "data" => { "object" => {
            "object" => "charge",
            "billing_details" => { "name" => user.id.to_s },
          } } },
          kind: :charge_failed,
          status: :pending,
          fingerprint: "abc123",
        )
        assert_nil stripe_webhook.user_id

        stripe_webhook.save! # trigger #set_user_id

        assert_equal user.id, stripe_webhook.user_id
      end

      test "does not set the user_id field from billing_details.name when the value is not numeric" do
        stripe_webhook = Billing::StripeWebhook.new(
          payload: { "data" => { "object" => {
            "object" => "charge",
            "billing_details" => { "name" => "Some random value" },
          } } },
          kind: :charge_failed,
          status: :pending,
          fingerprint: "abc123",
        )
        assert_nil stripe_webhook.user_id

        stripe_webhook.save! # trigger #set_user_id

        assert_nil stripe_webhook.user_id
      end

      test "sets the user_id field to the Stripe Connect account's owner" do
        user = create(:user, :verified)
        listing = create(:sponsors_listing, sponsorable: user)
        stripe_account = create(:stripe_connect_account, sponsors_listing: listing)
        stripe_webhook = Billing::StripeWebhook.new(
          payload: { "data" => { "object" => {
            "object" => "transfer",
            "destination" => stripe_account.stripe_account_id,
          } } },
          kind: :transfer_created,
          status: :pending,
          fingerprint: "abc123",
        )
        assert_nil stripe_webhook.user_id

        stripe_webhook.save! # trigger #set_user_id

        assert_equal user.id, stripe_webhook.user_id
      end
    end

    context "#perform" do
      test "updates the status and processed_at" do
        stripe_webhook = build(:stripe_webhook, :pending)

        handler = mock
        handler.expects(:perform).once.with(stripe_webhook)
        stripe_webhook.stubs(:handler).returns(handler)

        stripe_webhook.perform

        stripe_webhook.reload
        assert_equal "processed", stripe_webhook.status
        refute_nil stripe_webhook.processed_at
      end
    end

    context "payout creation" do
      test "clears latest payout cache key on payout_created creation" do
        stripe_account = create(:stripe_connect_account)
        cache_key = stripe_account.latest_payout_status_cache_key
        Billing::Kv.store.set(cache_key, "some value")
        assert_equal "some value", Billing::Kv.store.get(cache_key).value { nil }

        create(:stripe_webhook, :payout_created, account: stripe_account.stripe_account_id)

        assert_nil Billing::Kv.store.get(cache_key).value { nil }
      end

      test "clears latest payout cache key on payout_failed creation" do
        stripe_account = create(:stripe_connect_account)
        cache_key = stripe_account.latest_payout_status_cache_key
        Billing::Kv.store.set(cache_key, "some value")
        assert_equal "some value", Billing::Kv.store.get(cache_key).value { nil }

        create(:stripe_webhook, :payout_failed, account: stripe_account.stripe_account_id)

        assert_nil Billing::Kv.store.get(cache_key).value { nil }
      end

      test "does not clear latest payout cache key when creating a non-payout webhook" do
        stripe_account = create(:stripe_connect_account)
        cache_key = stripe_account.latest_payout_status_cache_key
        Billing::Kv.store.set(cache_key, "some value")
        assert_equal "some value", Billing::Kv.store.get(cache_key).value { nil }

        create(:stripe_webhook, :transfer_created, account: stripe_account.stripe_account_id)

        assert_equal "some value", Billing::Kv.store.get(cache_key).value { nil }
      end
    end

    context "#stripe_event" do
      test "returns a Stripe::Event from the webhook's payload" do
        # see test/fixtures/billing/stripe/events/payout_created.json
        webhook = build(:stripe_webhook, :payout_created)

        result = webhook.stripe_event

        assert_instance_of ::Stripe::Event, result
        refute_nil result.created
        assert_equal DateTime.new(2019, 7, 16, 19, 31, 23), Time.at(result.created).to_datetime
        assert_equal "payout.created", result.type
        assert_equal "event", result.object
        assert_instance_of ::Stripe::StripeObject, result.data
        assert_instance_of ::Stripe::Payout, result.data.object
        assert_equal "po_1EwwMxFxJZYgoodPlzd0x11wd", result.data.object.id
        assert_equal "payout", result.data.object.object
        assert_equal 500, result.data.object.amount
      end
    end

    context "#stripe_object_created" do
      test "returns the creation time from the Stripe JSON payload" do
        # see test/fixtures/billing/stripe/events/payout_created.json
        webhook = build(:stripe_webhook, :payout_created)
        assert_equal DateTime.new(2019, 7, 16, 19, 31, 23), webhook.stripe_object_created
      end
    end

    context "#stripe_object_id" do
      test "returns the object ID from the Stripe payload" do
        payout_id = "po_1EhSIvEQsq43iHhXWQiknnQB"
        webhook = build(:stripe_webhook, :payout_created, object: { id: payout_id })
        assert_equal payout_id, webhook.stripe_object_id
      end
    end
  end
end
