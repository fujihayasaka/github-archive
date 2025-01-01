# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::SendFailureNotificationTest < GitHub::BillingTestCase
    setup { ActionMailer::Base.deliveries.clear }

    context ".perform" do
      test "sends a failure notification to a paypal User" do
        user = create :paypal_user
        plan_subscription = create :billing_plan_subscription, user: user

        message = "This does not work"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "paypal_failure", args: [user, message]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: message
        end

        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.to, user.email
        assert_match "We had a problem", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          assert_match "PayPal", body
          assert_match "This does not work", body
        end
      end

      test "sends a failure notification to a paypal Business" do
        business = create :business
        payment_method = create :paypal_payment_method, :zuora, paypal_email: "whoever@example.com"
        payment_method.update_attribute(:customer, business.customer)
        plan_subscription = create :billing_plan_subscription, customer: business.customer, user: nil

        message = "This does not work"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "paypal_failure", args: [business, message]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: message
        end

        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.bcc, business.billing_email
        assert_match "We had a problem", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          assert_match "PayPal", body
          assert_match "This does not work", body
        end
      end

      test "sends a failure notification to an expiring card User" do
        user = create :credit_card_user
        plan_subscription = create :billing_plan_subscription, user: user
        user.payment_method.update_column :expiration_year, ::GitHub::Billing.today.year - 1

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_expired_failure", args: [user]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: "This does not work"
        end
        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.to, user.email
        assert_match "has expired", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          assert_match "has expired", body
        end
      end

      test "sends a failure notification to an expiring card Business" do
        business = create(:business, customer: create(:customer, :zuora, billing_type: "card"))
        customer = business.customer
        plan_subscription = create :billing_plan_subscription, customer: business.customer, user: nil
        customer.payment_method.update_column :expiration_year, ::GitHub::Billing.today.year - 1

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_expired_failure", args: [business]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: "This does not work"
        end
        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.bcc, business.billing_email
        assert_match "has expired", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          assert_match "has expired", body
        end
      end

      test "sends a failure notification to a credit card User" do
        user = create :credit_card_user
        plan_subscription = create :billing_plan_subscription, user: user

        message = "This does not work"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [user, message]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: message
        end
        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.to, user.email
        assert_match "We had a problem", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          refute_match "PayPal", body
          assert_match "This does not work", body
        end
      end

      test "sends a failure notification to a credit card Business" do
        business = create(:business, customer: create(:customer, :zuora, billing_type: "card"))
        customer = business.customer
        plan_subscription = create :billing_plan_subscription, customer: business.customer, user: nil

        message = "This does not work"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [business, message]) do
          PlanSubscription::SendFailureNotification.perform \
            plan_subscription,
            message: message
        end
        customer_email = ActionMailer::Base.deliveries.first

        assert_equal 1, ActionMailer::Base.deliveries.size
        assert_includes customer_email.bcc, business.billing_email
        assert_match "We had a problem", customer_email.subject
        [customer_email.text_part.body.to_s, customer_email.html_part.decoded].each do |body|
          refute_match "PayPal", body
          assert_match "This does not work", body
        end
      end
    end
  end
end
