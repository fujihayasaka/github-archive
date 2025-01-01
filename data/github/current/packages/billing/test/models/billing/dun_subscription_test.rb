# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class DunSubscriptionTest < GitHub::BillingTestCase
    include GitHub::BrainTree::TestHelper
    include GitHub::ZuoraTestHelper
    include ActionMailer::TestHelper
    include DogstatsTestHelpers

    setup do
      GitHub.flipper[:new_zuora_rate_plan_charges].enable

      ActionMailer::Base.deliveries.clear

      # Accounts need at least one past successful payment to be eligible for dunning
      @user_with_one_successful_payment = create(:credit_card_user)
      create(:billing_transaction, user: @user_with_one_successful_payment, amount_in_cents: 1_00, last_status: :settled)
      @business_with_one_successful_payment = create(:business, :with_credit_card, billing_email: "dunning@example.com")
      create(:billing_transaction, customer: @business_with_one_successful_payment.customer, amount_in_cents: 1_00, last_status: :settled)

      # Stub out the job so we don't make API calls to Zuora
      Billing::CancelPastDueProductsJob.any_instance.stubs(:perform)
    end

    def dun_subscription(account, message: nil, subscription: nil, transaction: nil, skip_notification: false)
      Billing::DunSubscription.perform \
        account,
        message: message,
        braintree_subscription: subscription,
        braintree_transaction: transaction,
        skip_notification: skip_notification
    end

    test "increments billing attempts properly" do
      assert_equal 0, @user_with_one_successful_payment.billing_attempts

      dun_subscription @user_with_one_successful_payment
      assert_equal 1, @user_with_one_successful_payment.reload.billing_attempts
    end

    test "increments billing attempts properly for Business" do
      assert_equal 0, @business_with_one_successful_payment.billing_attempts

      dun_subscription @business_with_one_successful_payment
      assert_equal 1, @business_with_one_successful_payment.reload.billing_attempts
    end

    test "enqueues CancelPastDueProductsJob once if the account is disabled" do
      @user_with_one_successful_payment.update(billing_attempts: 3)

      assert @user_with_one_successful_payment.enabled?

      assert_enqueued_jobs(1, only: [Billing::CancelPastDueProductsJob]) do
        dun_subscription @user_with_one_successful_payment
      end

      assert @user_with_one_successful_payment.disabled?
    end

    test "enqueues CancelPastDueProductsJob once if the account is already disabled" do
      @user_with_one_successful_payment.update(disabled: true, billing_attempts: 3)

      assert @user_with_one_successful_payment.disabled?

      assert_enqueued_jobs(1, only: [Billing::CancelPastDueProductsJob]) do
        dun_subscription @user_with_one_successful_payment
      end

      assert @user_with_one_successful_payment.disabled?
    end

    context "sends notifications" do
      test "sends credit card failure email" do
        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [@user_with_one_successful_payment, message]) do
          dun_subscription @user_with_one_successful_payment
        end
        mail = ActionMailer::Base.deliveries.first
        assert_includes mail.to, @user_with_one_successful_payment.email
        assert_match "had a problem billing",      mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your credit card",      body
          assert_match "Call your payment provider", body
        end
      end

      test "doesn't send notification when skip_notification is true" do
        assert_no_emails do
          dun_subscription @user_with_one_successful_payment, skip_notification: true
        end
      end

      test "sends credit card failure email to Organizations" do
        org = create :credit_card_org, billing_email: "failures@example.com"

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [org, message]) do
          dun_subscription org
        end

        mail = ActionMailer::Base.deliveries.first
        assert_includes mail.to, "failures@example.com"
        assert_match "had a problem billing",      mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your credit card",      body
          assert_match "Call your payment provider", body
        end
      end

      test "sends credit card failure email to Businesses" do
        customer = create :credit_card_customer
        business = create :business, billing_email: "failures@example.com", customer: customer
        business.customer.update billing_type: "card"

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [business, message]) do
          dun_subscription business
        end

        mail = ActionMailer::Base.deliveries.first

        assert_includes mail.bcc, "failures@example.com"
        assert_match "had a problem billing",      mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your credit card",      body
          assert_match "Call your payment provider", body
        end
      end

      test "sends credit card failure email with braintree transaction" do
        braintree_transaction = failed_transaction
        user = create :credit_card_user

        message = "Do Not Honor"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [user, message]) do
          dun_subscription user, transaction: braintree_transaction
        end
        mail = ActionMailer::Base.deliveries.first

        assert_match "had a problem billing", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your credit card", body
          assert_match "Do Not Honor",          body    # failed transaction message
        end
      end

      test "sends over billing attempts email" do
        user = create :credit_card_user,
          billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "over_billing_attempts_limit_failure", args: [user, message]) do
          dun_subscription user
        end
        mail = ActionMailer::Base.deliveries.first
        assert_includes mail.to, user.email
        assert_match "had a problem billing", mail.subject.to_s

        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your credit card", body
          assert_match "last two weeks",        body
          refute_match "disabled access to your private repositories", body
        end
      end

      test "sends over billing attempts email to Businesses" do
        business = create :business, billing_email: "failures@example.com"
        business.customer.update billing_type: "card"
        business.customer.update billing_attempts: Business::BillingDependency::BILLING_ATTEMPTS_LIMIT

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "over_billing_attempts_limit_failure", args: [business, message]) do
          dun_subscription business
        end

        mail = ActionMailer::Base.deliveries.first

        assert_includes mail.bcc, business.billing_email
        assert_match "had a problem billing", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "bill your account", body
          assert_match "last two weeks",    body
        end
      end

      test "sends credit card expired email" do
        user          = create(:credit_card_user)
        one_month_ago = GitHub::Billing.today - 1.month

        user.payment_method.update!(expiration_month: one_month_ago.month, expiration_year: one_month_ago.year)
        assert_predicate user.reload, :card_expired?

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_expired_failure", args: [user]) do
          dun_subscription user
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "Your credit card has expired", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "credit card has expired", body
        end
      end

      test "sends credit card expired email to Businesses" do
        customer = create :credit_card_customer
        business = create :business, billing_email: "failures@example.com", customer: customer
        business.customer.update billing_type: "card"
        one_month_ago = GitHub::Billing.today - 1.month

        business.payment_method.expiration_month = one_month_ago.month
        business.payment_method.expiration_year  = one_month_ago.year

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_expired_failure", args: [business]) do
          dun_subscription business
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "Your credit card has expired", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "credit card has expired", body
        end
      end

      test "sends paypal failure email for paypal account" do
        user = create(:paypal_user)

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "paypal_failure", args: [user, message]) do
          dun_subscription user
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "We had a problem billing your account", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "trying to bill your PayPal account",    body
        end
      end

      test "sends paypal failure email with custom message" do
        user = create(:paypal_user)

        message = "pay me"
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "paypal_failure", args: [user, message]) do
          dun_subscription user, message: message
        end
        mail = ActionMailer::Base.deliveries.first
        assert_match "We had a problem billing your account", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "trying to bill your PayPal account",    body
          assert_match "pay me",                                body
        end
      end

      test "sends paypal failure email for paypal account for Businesses" do
        customer = create :paypal_customer
        business = create :business, billing_email: "failures@example.com", customer: customer

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "paypal_failure", args: [business, message]) do
          dun_subscription business
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "We had a problem billing your account", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "trying to bill your PayPal account", body
        end
      end

      test "sends no payment method email to Organizations" do
        org = create :organization, billing_email: "failures@example.com"

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "no_payment_failure", args: [org]) do
          dun_subscription org
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "We had a problem billing your account", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "currently no payment method on file",    body
        end
      end

      test "sends no payment method email to Businesses" do
        business = create :business, billing_email: "failures@example.com"

        assert_performed_email(mailer: "BillingNotificationsMailer", action: "no_payment_failure", args: [business]) do
          dun_subscription business
        end

        mail = ActionMailer::Base.deliveries.first
        assert_match "We had a problem billing your account", mail.subject.to_s
        [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
          assert_match "currently no payment method on file",    body
        end
      end

      test "sends email if user is on their first payment failure" do
        @user_with_one_successful_payment.update(billing_attempts: 1)

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [@user_with_one_successful_payment, message]) do
          dun_subscription @user_with_one_successful_payment
        end
        assert_dogstats_increment(1, "billing.dunning_subscription.notify", tags: [
          "notification_type:cc_failure",
          "attempts:1"
        ])
      end

      test "sends email if user is on their second payment failure" do
        @user_with_one_successful_payment.update(billing_attempts: 2)

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "cc_failure", args: [@user_with_one_successful_payment, message]) do
          dun_subscription @user_with_one_successful_payment
        end
        assert_dogstats_increment(1, "billing.dunning_subscription.notify", tags: [
          "notification_type:cc_failure",
          "attempts:2"
        ])
      end

      test "sends email if user is at their max allowed payment failures" do
        @user_with_one_successful_payment.update(billing_attempts: User::BillingDependency::BILLING_ATTEMPTS_LIMIT)

        message = "Call your payment provider to resolve this issue."
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "over_billing_attempts_limit_failure", args: [@user_with_one_successful_payment, message]) do
          dun_subscription @user_with_one_successful_payment
        end
        assert_dogstats_increment(1, "billing.dunning_subscription.notify", tags: [
          "notification_type:over_billing_attempts_limit_failure",
          "attempts:#{::User::BillingDependency::BILLING_ATTEMPTS_LIMIT}"
        ])
      end
    end

    context "disabling account" do
      test "disables if charge failure exceeds billing attempts limit for User" do
        user = create(:credit_card_user,
                      # This needs to be set so that its been successfully billed, otherwise
                      # the dunning rules change.(billing attempt limit is at 0)
                      billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS,
                     )

        # Account needs at least one past successful payment to be eligible for dunning
        create(:billing_transaction, user: user, amount_in_cents: 1_00, last_status: :settled)

        # First Attempt, 1 biling attempt
        dun_subscription user
        refute user.disabled?
        assert_equal 1, user.reload.billing_attempts

        # Second Attempt, 2 billing attempts(+7 days)
        # NB: With the changes, this assumes that BT would have sent back the
        # failure count. We need to modify the state to match that.
        user.update_column :billing_attempts, 2
        dun_subscription user
        refute user.disabled?

        # Last Attempt, 3 billing attempts(+8 more days)
        user.update_column :billing_attempts, 3
        dun_subscription user
        assert user.disabled?

        # Out of Range Attempts because of old data.
        user.update_column :billing_attempts, 4
        dun_subscription user
        assert user.disabled?
      end

      test "disables if charge failure exceeds billing attempts limit for Business" do
        # This needs to be set so that it has been successfully billed, otherwise
        # the dunning rules change. (billing attempt limit is at 0)
        customer = create :credit_card_customer,
          billing_end_date: T.unsafe(GitHub::Billing.today) - Business::BillingDependency::DUNNING_DAYS - 1.day
        business = create :business, customer: customer

        # Account needs at least one past successful payment to be eligible for dunning
        create(:billing_transaction, customer: customer, amount_in_cents: 1_00, last_status: :settled)

        # First Attempt, 1 billing attempt
        dun_subscription business
        refute_predicate business, :disabled?
        assert_equal 1, business.reload.billing_attempts

        # Second Attempt, 2 billing attempts (+7 days)
        business.customer.update_column :billing_attempts, 2
        dun_subscription business
        refute_predicate business.reload, :disabled?

        # Last Attempt, 3 billing attempts (+8 more days)
        business.customer.update_column :billing_attempts, 3
        dun_subscription business
        assert_predicate business.reload, :disabled?

        # Out of Range Attempts because of old data.
        business.customer.update_column :billing_attempts, 4
        dun_subscription business
        assert_predicate business.reload, :disabled?
      end

      test "disables if User only has zero charge transactions" do
        user = create :credit_card_user, billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS

        # Zero charge transaction
        create(:billing_transaction, user: user, amount_in_cents: 0, last_status: :settled)

        dun_subscription user
        assert user.never_successfully_billed?
        assert user.disabled?
      end

      test "disables if Business only has zero charge transactions" do
        customer = create :credit_card_customer,
          billing_end_date: GitHub::Billing.today - Business::BillingDependency::DUNNING_DAYS - 1.day
        business = create :business, customer: customer

        # Zero charge transaction
        create(:billing_transaction, customer: customer, amount_in_cents: 0, last_status: :settled)

        dun_subscription business
        assert_predicate business, :never_successfully_billed?
        assert_predicate business, :disabled?
      end

      test "disables if User has not been successfully billed" do
        user = create :credit_card_user

        dun_subscription user
        assert user.never_successfully_billed?
        assert user.disabled?
      end

      test "disables if Business has not been successfully billed" do
        customer = create :credit_card_customer
        business = create :business, customer: customer

        dun_subscription business
        assert_predicate business, :never_successfully_billed?
        assert_predicate business, :disabled?
      end
    end

    context "Zuora subscriptions" do
      test "cancels Zuora subscriptions when User is disabled" do
        GitHub.flipper[:billing_only_cancel_past_due_products].disable
        plan = GitHub::Plan.pro
        user = create(:user, plan: plan)
        zuora_successful_customer_account_creation(user)

        with_live_zuora("zuora/dunning_subscription_disabled_user") do
          user.reload

          sub_number = "A-S00005203"
          user.plan_subscription.update!(zuora_subscription_number: sub_number)

          user.update(
            billed_on: GitHub::Billing.today - User::BillingDependency::DUNNING_DAYS,
            billing_attempts: 3,
          )
          dun_subscription(user)
        end

        with_live_zuora("zuora/dunning_subscription_disabled_user_part_two") do
          sub_number = "A-S00005203"
          zuora_subscription = Billing::Zuora::Subscription.find(sub_number)

          refute_predicate zuora_subscription, :active?

          invoices = Billing::Zuora::Invoice.invoices_for_subscription(sub_number)

          assert T.must(invoices.first).balance.zero?
        end
      end

      test "cancels Zuora subscriptions when Business is disabled" do
        GitHub.flipper[:billing_only_cancel_past_due_products].disable
        customer = create :credit_card_customer
        business = create :business, customer: customer
        zuora_successful_customer_account_creation(business)
        synchronize_github_products_to_zuora
        with_live_zuora("zuora/dunning_subscription_disabled_business") do
          business.reload

          sub_number = "A-S00005204"
          create :billing_plan_subscription, \
            customer: business.customer,
            zuora_subscription_number: sub_number

          business.customer.update \
            billing_end_date: GitHub::Billing.today - Business::BillingDependency::DUNNING_DAYS - 1.day,
            billing_attempts: 3
          dun_subscription business
        end

        with_live_zuora("zuora/dunning_subscription_disabled_business_part_two") do
          sub_number = "A-S00005204"
          zuora_subscription = Billing::Zuora::Subscription.find(sub_number)

          refute_predicate zuora_subscription, :active?

          invoices = Billing::Zuora::Invoice.invoices_for_subscription(sub_number)

          assert_predicate T.must(invoices.first).balance, :zero?
        end
      end

      test "does not cancel Zuora subscriptions if User is still in dunning" do
        GitHub.flipper[:billing_only_cancel_past_due_products].disable
        synchronize_github_products_to_zuora
        with_live_zuora("zuora/dunning_subscription_enabled_user") do
          plan = GitHub::Plan.pro

          user = create(:user, plan: plan)
          zuora_successful_customer_account_creation(user)
          user.reload

          plan_subscription = user.plan_subscription

          Billing::PlanSubscription::Synchronizer.create(plan_subscription)

          zuora_subscription = user.plan_subscription.reload.zuora_subscription

          user.update(
            billed_on: GitHub::Billing.today,
            billing_attempts: 1,
          )
          user.customer.update(bill_cycle_day: user.billed_on.day)

          Billing::PlanSubscription::Synchronizer.expects(:cancel).never

          dun_subscription(user)

          zuora_subscription = Billing::Zuora::Subscription.find(zuora_subscription.id)
          assert_predicate zuora_subscription, :active?
        end
      end

      test "does not cancel Zuora subscriptions if Business is still in dunning" do
        GitHub.flipper[:billing_only_cancel_past_due_products].disable
        synchronize_github_products_to_zuora
        with_live_zuora("zuora/dunning_subscription_enabled_business") do
          customer = create :credit_card_customer
          business = create :business, customer: customer
          zuora_successful_customer_account_creation(business)

          business.reload

          plan_subscription = business.plan_subscription

          Billing::PlanSubscription::Synchronizer.create(plan_subscription)

          zuora_subscription = business.plan_subscription.reload.zuora_subscription

          business.customer.update \
            billing_end_date: GitHub::Billing.today,
            billing_attempts: 1

          Billing::PlanSubscription::Synchronizer.expects(:cancel).never

          dun_subscription business

          zuora_subscription = Billing::Zuora::Subscription.find(zuora_subscription.id)
          assert_predicate zuora_subscription, :active?
        end
      end
    end
  end
end
