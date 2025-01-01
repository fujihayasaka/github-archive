# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::SendReceiptTest < GitHub::BillingTestCase
    setup { ActionMailer::Base.deliveries.clear }

    context ".perform" do
      test "sends an email receipt for a User" do
        user = create :credit_card_user

        transaction_id = "abc123"
        plan_subscription = create :billing_plan_subscription, user: user
        billing_transaction = create :billing_transaction,
          user: plan_subscription.user,
          transaction_id: transaction_id,
          amount_in_cents: 500

        only = [ApplicationDeliveryJob]
        perform_enqueued_jobs(only: only) do
          PlanSubscription::SendReceipt.perform \
            plan_subscription,
            billing_transaction: billing_transaction
        end
        customer_email = ActionMailer::Base.deliveries.first
        bcc_email = ActionMailer::Base.deliveries.second

        body = customer_email.parts.first.body.to_s

        assert_equal 2, ActionMailer::Base.deliveries.size
        assert_includes customer_email.to, user.email
        assert_match "Payment Receipt", customer_email.subject
        assert_match "$5", body

        assert_includes bcc_email.to, "logs@github.com"
      end

      test "sends an email receipt for an Organization" do
        org = create :credit_card_org,
          billing_email: "receipts@example.com", plan: "bronze"

        ActionMailer::Base.deliveries.clear

        transaction_id = "abc123"
        plan_subscription = create :billing_plan_subscription, user: org
        billing_transaction = create :billing_transaction,
          user: plan_subscription.user,
          transaction_id: transaction_id,
          amount_in_cents: 500

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "receipt", args: [org, billing_transaction]) do
          PlanSubscription::SendReceipt.perform \
            plan_subscription,
            billing_transaction: billing_transaction
        end
        assert_equal 2, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.to, "receipts@example.com"
      end

      test "sends an email receipt for a Business" do
        transaction_id = "abc123"
        plan_subscription = create :billing_plan_subscription, :business_owned
        billing_transaction = create :billing_transaction,
          :business_owned,
          customer: plan_subscription.customer,
          transaction_id: transaction_id,
          amount_in_cents: 500
        business = billing_transaction.billable_entity
        business.update! billing_email: "receipts@example.com"
        assert business.is_a?(Business)

        ActionMailer::Base.deliveries.clear

        assert_performed_email(
          mailer: "BillingNotificationsMailer",
          action: "receipt",
          args: [business, billing_transaction]) do
          PlanSubscription::SendReceipt.perform \
            plan_subscription,
            billing_transaction: billing_transaction
        end
        assert_equal 2, ActionMailer::Base.deliveries.size
        email = ActionMailer::Base.deliveries.first
        assert_includes email.bcc, "receipts@example.com"
      end
    end
  end
end
