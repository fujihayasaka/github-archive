# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class ZuoraWebhookTest < GitHub::TestCase
    include DogstatsTestHelpers

    def webhook_payload(event_category: "PaymentProcessed", **attributes)
      {
        event_category: event_category,
      }.merge!(attributes).with_indifferent_access
    end

    context ".receive" do
      test "creates a ZuoraWebhook record and enqueues a processing job" do
        assert_difference "::Billing::ZuoraWebhook.count", 1 do
          Billing::ZuoraWebhook.receive(webhook_payload(
            AccountId: "2c92c0f961f9cf350161fde177ff0922",
          ))
        end

        zuora_webhook = T.must(::Billing::ZuoraWebhook.last)
        assert_equal "payment_processed", zuora_webhook.kind
        assert_equal "2c92c0f961f9cf350161fde177ff0922", zuora_webhook.account_id
        assert_predicate zuora_webhook, :pending?
        refute_predicate zuora_webhook, :processed?

        assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
        assert_dogstats_increment(1, "zuora.webhook", tags: ["category:payment_processed"])
      end

      test "handles spaces in event category into underscores" do
        assert_difference "::Billing::ZuoraWebhook.count", 1 do
          Billing::ZuoraWebhook.receive(webhook_payload(
            event_category: "Account Updated",
            AccountId: "2c92c0f961f9cf350161fde177ff0922",
          ))
        end

        zuora_webhook = T.must(::Billing::ZuoraWebhook.last)
        assert_equal "account_updated", zuora_webhook.kind
        assert_equal "2c92c0f961f9cf350161fde177ff0922", zuora_webhook.account_id
        assert_predicate zuora_webhook, :pending?
        refute_predicate zuora_webhook, :processed?

        assert_enqueued_with job: ZuoraWebhookJob, args: [zuora_webhook]
        assert_dogstats_increment(1, "zuora.webhook", tags: ["category:account_updated"])
      end

      test "handles the case where category is nil" do
        payload = { "AccountId" => "2c92c0f961f9cf350161fde177ff0922" }
        assert_no_difference "::Billing::ZuoraWebhook.count"  do
          Billing::ZuoraWebhook.receive(payload)
        end

        assert_no_enqueued_jobs only: ZuoraWebhookJob
        assert_dogstats_increment(1, "zuora.webhook", tags: ["category:"])
      end
    end

    context ".create" do
      test "handles account updated kind" do
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        assert webhook.valid?, webhook.errors.full_messages
      end
    end

    context "#account_deleted?" do
      test "returns true for webhooks without an associated account" do
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(nil)

        assert webhook.account_deleted?
      end

      test "returns true for users pending deletion" do
        user = create(:user)
        user.deleted = true
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(user)

        assert webhook.account_deleted?
      end

      test "returns false for active users" do
        user = create(:user)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(user)

        refute webhook.account_deleted?
      end

      test "returns false for active organizations" do
        organization = create(:organization)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(organization)

        refute webhook.account_deleted?
      end

      test "returns false for active businesses" do
        business = create(:business)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(business)

        refute webhook.account_deleted?
      end
    end

    context "#account_suspended?" do
      test "returns true for suspended users" do
        user = create(:user, suspended_at: Time.current.utc)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(user)

        assert webhook.account_suspended?
      end

      test "returns false for active users" do
        user = create(:user)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(user)

        refute webhook.account_suspended?
      end

      test "returns true for suspended organizations" do
        organization = create(:organization, suspended_at: Time.current.utc)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(organization)

        assert webhook.account_suspended?
      end

      test "returns false for active organizations" do
        organization = create(:organization)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(organization)

        refute webhook.account_suspended?
      end

      test "returns true for suspended businesses" do
        business = create(:business, suspended_at: Time.current.utc)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(business)

        assert webhook.account_suspended?
      end

      test "returns false for active businesses" do
        business = create(:business)
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(business)

        refute webhook.account_suspended?
      end

      test "returns false for webhooks without an associated account" do
        webhook = build(:zuora_webhook, :pending, kind: :account_updated)
        webhook.expects(:account).at_least_once.returns(nil)

        refute webhook.account_suspended?
      end
    end

    context "handler" do
      test "returns the correct handler for account updated" do
        webhook = create(:zuora_webhook, :pending, kind: :account_updated)
        assert_equal Billing::Zuora::Webhooks::AccountUpdated, webhook.handler
      end

      test "returns the correct handler for subscription deleted" do
        webhook = create(:zuora_webhook, :pending, kind: :subscription_deleted)
        assert_equal Billing::Zuora::Webhooks::SubscriptionDeleted, webhook.handler
      end
    end

    context "#perform" do
      test "raises an error if the webhook is being processed and we're unable to acquire the lock after multiple attempts" do
        zuora_webhook = create(:zuora_webhook, :pending)

        restraint = GitHub::Restraint.new
        restraint.expects(:lock!).times(7).raises(GitHub::Restraint::UnableToLock)
        Billing::ZuoraWebhook.any_instance.expects(:sleep).times(5)

        assert_raises Billing::ZuoraWebhook::UnableToLock do
          zuora_webhook.perform(restraint: restraint)
        end
      end

      test "returns true and marks the webhook as processed if the handler returns true" do
        zuora_webhook = build(:zuora_webhook, :pending)
        user = create(:user)
        customer = create(
          :customer, :zuora, customer_account_user: user, zuora_account_id: zuora_webhook.account_id)

        handler = mock
        handler.expects(:perform).once.with(zuora_webhook).returns(true)
        zuora_webhook.stubs(:handler).returns(handler)

        assert zuora_webhook.perform

        zuora_webhook.reload

        assert_equal "processed", zuora_webhook.status
        refute_nil zuora_webhook.processed_at
      end

      test "returns false and marks the webhook as ignored if the handler returns false" do
        zuora_webhook = build(:zuora_webhook, :pending)
        user = create(:user)
        customer = create(
          :customer, :zuora, customer_account_user: user, zuora_account_id: zuora_webhook.account_id)

        handler = mock
        handler.expects(:perform).once.with(zuora_webhook).returns(false)
        zuora_webhook.stubs(:handler).returns(handler)

        refute zuora_webhook.perform

        zuora_webhook.reload

        assert_equal "ignored", zuora_webhook.status
        refute_nil zuora_webhook.processed_at
      end
    end

    context "#sales_ops_issue_details" do
      test "returns the SalesOperationsIssueDetails for a given webhook" do
        zuora_webhook = build(:zuora_webhook, :subscription_created, :pending)
        issue_details = zuora_webhook.sales_ops_issue_details

        assert_instance_of Billing::Zuora::SalesOperationsIssueDetails, issue_details
      end
    end

    test "throw an error if an investigation_note is empty when the the webhook status is set to investigating" do
      webhook = build(:zuora_webhook, :pending, kind: :account_updated)

      assert_raises(ActiveRecord::RecordInvalid) do
        webhook.update(status: :investigating, investigation_notes: nil)
        webhook.save!
      end
    end
  end
end
