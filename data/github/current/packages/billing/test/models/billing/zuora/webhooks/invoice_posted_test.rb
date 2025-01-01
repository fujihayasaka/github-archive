# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::InvoicePostedTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:credit_card_user, plan: GitHub::Plan.pro)
    @plan_subscription = create(:billing_plan_subscription,
      user: @user,
      zuora_subscription_id: SecureRandom.hex(16),
      zuora_subscription_number: "A-S01234567"
    )

    @business = create(:business)
    @business_plan_subscription = create(:billing_plan_subscription, :business_owned,
      customer: @business.customer,
      zuora_subscription_id: SecureRandom.hex(16),
      zuora_subscription_number: "A-S01234756"
    )

    @org = create(:credit_card_organization)
    @org_plan_subscription = create(:billing_plan_subscription, :zuora, user: @org,
      purpose: :sponsors,
      zuora_subscription_id: SecureRandom.hex(16),
      zuora_subscription_number: "A-S01234569")
    @org_sponsorship = create(:sponsorship, sponsor: @org)

    customer_account = create(:customer_account, :zuora_paypal)
    @paypal_sponsor = customer_account.user
    @paypal_sponsor_plan_sub = create(:billing_plan_subscription, :zuora, user: @paypal_sponsor,
      customer: customer_account.customer)
    @paypal_sponsor.emails.first.verify!
    @paypal_sponsorship1, @paypal_sponsorship2 = create_pair(:sponsorship, sponsor: @paypal_sponsor)
    @paypal_one_time_sponsorship = create(:sponsorship, :one_time, sponsor: @paypal_sponsor)
  end

  setup do
    disable_feature_flag(:billing_schedule_synchronization_after_invoice_posted)
    synchronize_github_products_to_zuora
  end

  sig do
    params(plan_subscription: T.nilable(Billing::PlanSubscription))
      .returns(T::Hash[Symbol, T.untyped])
  end
  def stub_zuora_subscription(plan_subscription: nil)
    plan_subscription ||= @plan_subscription
    test_subscription_id = plan_subscription.zuora_subscription_id
    test_subscription_number = plan_subscription.zuora_subscription_number

    test_subscription_data = FactoryBot.attributes_for(
      :zuora_subscription,
      id: test_subscription_id,
      subscriptionNumber: test_subscription_number
    )

    GitHub.zuorest_client.stubs(:get_subscription)
      .with(test_subscription_number)
      .returns(test_subscription_data)

    test_subscription_data
  end

  def stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 3)
    GitHub.zuorest_client.stubs(:get_payment_method).
    with(anything).
    returns({
      "NumConsecutiveFailures" => number_of_consecutive_payment_failures
    })
  end

  context "#perform" do
    test "does nothing for a deleted account" do
      zuora_webhook = build(:zuora_webhook, :invoice_posted, account_id: @plan_subscription.zuora_account_id)
      @user.destroy
      zuora_webhook.perform
      assert_predicate zuora_webhook, :ignored?
    end

    test "cancels external subscriptions for a suspended account" do
      zuora_webhook = build(:zuora_webhook, :invoice_posted, account_id: @plan_subscription.zuora_account_id)
      @user.suspend("Did something bad")
      assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
        zuora_webhook.perform
      end
      assert_predicate zuora_webhook, :ignored?
    end

    test "does nothing when there is no plan subscription" do
      zuora_webhook = build(:zuora_webhook, :invoice_posted, account_id: @plan_subscription.zuora_account_id)
      @plan_subscription.destroy
      zuora_webhook.perform
      assert_predicate zuora_webhook, :ignored?
    end

    test "records a no charge transaction when the invoice amount is zero" do
      invoice_data = stub_zuora_get_invoice(amount: 0)
      stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assert_empty @user.billing_transactions

      assert_difference(-> { Billing::BillingTransaction.count }) do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
      assert transaction = @user.reload.billing_transactions.last
      assert_equal Billing::Money.new(0), transaction.amount
      assert_equal @plan_subscription, transaction.plan_subscription
    end

    test "updates the local subscription from the zuora subscription data for zero amount invoices" do
      enable_feature_flag(:new_zuora_rate_plan_charges)
      invoice_data = stub_zuora_get_invoice(amount: 0)
      zuora_sub_attributes = stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      zuora_charges = zuora_sub_attributes[:ratePlans].flat_map { |rp| rp[:ratePlanCharges] }

      refute_nil @plan_subscription.zuora_subscription
      assert_equal 0, @plan_subscription.subscription_rate_plan_charges.count

      assert_difference "Billing::PlanSubscription::ZuoraRatePlanCharge.count", zuora_charges.count do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
      assert_equal zuora_charges.count, @plan_subscription.reload.subscription_rate_plan_charges.count
    end

    context "user has an apple iap subscription and an invoice amount of zero" do
      test "does not reset billing status when a Zuora subscription is not present" do
        invoice_data = stub_zuora_get_invoice(amount: 0)
        plan_subscription = create(:billing_plan_subscription, :apple_iap)
        stub_zuora_subscription(plan_subscription: plan_subscription)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: plan_subscription.zuora_account_id,
          payload: { "AccountId" => plan_subscription.zuora_account_id, "InvoiceId" => invoice_data[:id] },
        )

        ::Billing::ResetBillingStatus.expects(:perform).never

        zuora_webhook.perform
        assert_predicate zuora_webhook, :processed?
      end

      test "resets billing status when a Zuora subscription is present" do
        invoice_data = stub_zuora_get_invoice(amount: 0)
        plan_subscription = create(:billing_plan_subscription, :apple_iap, :zuora)
        stub_zuora_subscription(plan_subscription: plan_subscription)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        ::Billing::ResetBillingStatus.expects(:perform).once

        zuora_webhook.perform
        assert_predicate zuora_webhook, :processed?
      end

      test "updates the local subscription from the zuora subscription data when present" do
        enable_feature_flag(:new_zuora_rate_plan_charges)
        invoice_data = stub_zuora_get_invoice(amount: 0)
        plan_subscription = create(:billing_plan_subscription, :apple_iap, :zuora)
        zuora_sub_attributes = stub_zuora_subscription(plan_subscription: plan_subscription)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        zuora_charges = zuora_sub_attributes[:ratePlans].flat_map { |rp| rp[:ratePlanCharges] }

        refute_nil plan_subscription.zuora_subscription

        assert_equal 0, plan_subscription.subscription_rate_plan_charges.count

        assert_difference "Billing::PlanSubscription::ZuoraRatePlanCharge.count", zuora_charges.count do
          zuora_webhook.perform
        end

        assert_predicate zuora_webhook, :processed?
        assert_equal zuora_charges.count, plan_subscription.reload.subscription_rate_plan_charges.count
      end
    end

    context "user has billing locked" do
      test "does not sync subscription if user has a canceled subscription due to their billing being disabled with 3 failed payments associated to their current payment method and the invoice amount is zero" do
        user_with_billing_in_bad_standing = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        canceled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_in_bad_standing,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )

        invoice_data = stub_zuora_get_invoice(amount: 0)
        stub_zuora_subscription(plan_subscription: canceled_plan_subscription)
        stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 3)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: canceled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => canceled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        assert_empty user_with_billing_in_bad_standing.billing_transactions

        assert_difference(-> { Billing::BillingTransaction.count }) do
          zuora_webhook.perform
        end

        assert_predicate zuora_webhook, :processed?
        assert transaction = user_with_billing_in_bad_standing.reload.billing_transactions.last
        assert_equal Billing::Money.new(0), transaction.amount

        current_plan_subscription = user_with_billing_in_bad_standing.plan_subscription.reload
        zuora_subscription = current_plan_subscription.reload.zuora_subscription
        assert_nil zuora_subscription
      end

      test "the user's billing status is not reset if they don't have an active plan subscription, their payment method has 3 consecutive failures, and the invoice amount is 0" do
        user_with_billing_in_bad_standing = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        canceled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_in_bad_standing,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )

        invoice_data = stub_zuora_get_invoice(amount: 0)
        stub_zuora_subscription(plan_subscription: canceled_plan_subscription)
        stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 3)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: canceled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => canceled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        zuora_webhook.perform

        user_with_billing_in_bad_standing.reload

        assert_predicate zuora_webhook, :processed?
        assert_equal user_with_billing_in_bad_standing.billing_attempts, 3
        assert_equal user_with_billing_in_bad_standing.disabled?, true
      end

      test "raises a retryable webhook error if the subscription synchronization is locked" do
        user_with_billing_locked = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        cancelled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_locked,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )
        invoice_data = stub_zuora_get_invoice(amount: 0)
        stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 0)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: cancelled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => cancelled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        GitHub::Restraint.new.lock! cancelled_plan_subscription.lock_key, 1, 1.minute do
          assert_raises Billing::ZuoraWebhook::RetryableError do
            zuora_webhook.perform
          end
        end
      end

      test "the plan subscription is synced if the user has their billing account disabled but less than 3 consecutive payment failures associated to their current payment method" do
        user_with_billing_locked = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        canceled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_locked,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )
        invoice_data = stub_zuora_get_invoice(amount: 0)
        stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 0)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: canceled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => canceled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        new_subscription_number = "A-S918880b01359"
        GitHub.zuorest_client.stubs(:create_subscription).with(anything, ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER).returns(
          { "success" => true, "Id" => nil, "id" => nil, "subscriptionNumber" => new_subscription_number, "contractedMrr" => 0, "subscriptions" => [] }
        )

        # This will be the new plan subscription replacing the canceled one
        new_plan_subscription = canceled_plan_subscription
        new_plan_subscription.zuora_subscription_number = new_subscription_number
        new_plan_subscription.zuora_subscription_id = SecureRandom.hex(16)

        stub_zuora_subscription(plan_subscription: new_plan_subscription)

        zuora_webhook.perform

        updated_plan_subscription = user_with_billing_locked.reload.plan_subscription
        updated_zuora_subscription_number = updated_plan_subscription.reload.zuora_subscription_number

        assert_predicate zuora_webhook, :processed?
        assert_equal updated_zuora_subscription_number, new_subscription_number

        assert transaction = user_with_billing_locked.reload.billing_transactions.last
        assert_equal Billing::Money.new(0), transaction.amount
      end

      test "a new subscription is created if the user has a canceled subscription and when the invoice amount is zero" do
        user_with_billing_in_bad_standing = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        canceled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_in_bad_standing,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )

        invoice_data = stub_zuora_get_invoice(amount: 0)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: canceled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => canceled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        new_subscription_number = "A-S918880b01359"
        new_subscription_id = SecureRandom.hex(16)
        GitHub.zuorest_client.stubs(:create_subscription).with(anything, ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER).returns(
          { "success" => true, "Id" => nil, "id" => new_subscription_id, "subscriptionNumber" => new_subscription_number, "contractedMrr" => 0, "subscriptions" => [] }
        )

        # This will be the new plan subscription replacing the canceled one
        new_plan_subscription = canceled_plan_subscription
        new_plan_subscription.zuora_subscription_number = new_subscription_number
        new_plan_subscription.zuora_subscription_id = new_subscription_id

        stub_zuora_subscription(plan_subscription: new_plan_subscription)

        assert_empty user_with_billing_in_bad_standing.billing_transactions

        assert_difference(-> { Billing::BillingTransaction.count }) do
          zuora_webhook.perform
        end

        updated_plan_subscription = user_with_billing_in_bad_standing.reload.plan_subscription
        updated_zuora_subscription_number = updated_plan_subscription.reload.zuora_subscription_number

        assert_predicate zuora_webhook, :processed?
        assert_equal updated_zuora_subscription_number, new_subscription_number

        assert transaction = user_with_billing_in_bad_standing.reload.billing_transactions.last
        assert_equal Billing::Money.new(0), transaction.amount
      end

      test "the user's billing status is not reset if they have their billing locked, a canceled plan subscription, a zuora balance of 0 and and if the invoice amount is zero " do
        user_with_billing_in_bad_standing = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        canceled_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_in_bad_standing,
          zuora_subscription_id: nil,
          zuora_subscription_number: nil
        )

        invoice_data = stub_zuora_get_invoice(amount: 0)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: canceled_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => canceled_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        zuora_webhook.perform

        user_with_billing_in_bad_standing.reload

        assert_predicate zuora_webhook, :processed?
        assert_equal user_with_billing_in_bad_standing.billing_attempts, 3
        assert user_with_billing_in_bad_standing.disabled?
      end

      test "the user's billing status is not reset if they have an active plan subscription, have their billing disabled, their payment method has 3 consecutive failures, and the invoice amount is 0" do
        user_with_billing_in_bad_standing = create(:credit_card_user, :with_billing_locked, plan: GitHub::Plan.pro, billing_attempts: 3)

        active_plan_subscription = create(:billing_plan_subscription,
          user: user_with_billing_in_bad_standing,
          zuora_subscription_id: SecureRandom.hex(16),
          zuora_subscription_number: "A-S01234578"
        )

        invoice_data = stub_zuora_get_invoice(amount: 0)
        stub_zuora_subscription(plan_subscription: active_plan_subscription)
        stub_zuora_external_payment_method(number_of_consecutive_payment_failures: 3)

        zuora_webhook = build(
          :zuora_webhook,
          :invoice_posted,
          account_id: active_plan_subscription.zuora_account_id,
          payload: {
            "AccountId" => active_plan_subscription.zuora_account_id,
            "InvoiceId" => invoice_data[:id]
          },
        )

        zuora_webhook.perform

        user_with_billing_in_bad_standing.reload

        assert_predicate zuora_webhook, :processed?
        assert_equal user_with_billing_in_bad_standing.billing_attempts, 3
        assert_equal user_with_billing_in_bad_standing.disabled?, true
      end
    end

    test "enqueues negative invoice job when an invoice balance is negative" do
      invoice_data = stub_zuora_get_invoice(balance: -8.99, amount: 8.99)
      stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      time = Time.current
      travel_to(time) do
        assertion = {
          job: Billing::Zuora::NegativeInvoiceJob,
          args: [{ invoice_id: invoice_data[:id] }],
          queue: "billing",
          at: time + 1.hour
        }

        assert_enqueued_jobs 1 do
          zuora_webhook.perform
        end

        assert_predicate zuora_webhook, :processed?
        assert_enqueued_with(**assertion)
        assert_dogstats_count_value(899, "zuora.invoices.balance_in_cents",
          tags: ["class:billing/zuora/webhooks/invoice_posted"]
        )
        assert_dogstats_increment("zuora.invoices",
          tags: ["balance:negative", "class:billing/zuora/webhooks/invoice_posted"]
        )
      end
    end

    test "enqueues positive invoice catchup disable job when the balance is positive" do
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      zuora_webhook.perform

      assert_predicate zuora_webhook, :processed?
      assert_enqueued_jobs 1, only: [Billing::PositiveInvoiceCatchupDisableJob]
    end

    test "enqueues invoice collection when the balance is positive for sponsors-invoiced plan subscription" do
      sponsors_invoiced_plan_subscription = create(:billing_plan_subscription, :zuora, :sponsors_invoiced)
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription(plan_subscription: sponsors_invoiced_plan_subscription)
      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: sponsors_invoiced_plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => sponsors_invoiced_plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assertion = {
        job: SponsorsBillingCreditBalanceInvoiceCollectionJob,
        args: [sponsors_invoiced_plan_subscription.user, { invoice_id: invoice_data[:id] }],
        queue: "billing",
      }
      assert_enqueued_with(**assertion) do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
    end

    test "does not enqueue invoice collection when the balance is positive for general-purpose plan subscription" do
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assert_no_enqueued_jobs only: [SponsorsBillingCreditBalanceInvoiceCollectionJob] do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
    end

    test "dunning period gets created for a positive balance for an RBI User" do
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription

      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => 8.99 } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)

      fake_zuora_object_account = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account, metrics: { balance: 8.99 }))
      )
      Customer.any_instance.stubs(:zuora_object_account).returns(fake_zuora_object_account)

      user = create(:india_based_credit_card_user, :disabled_by_india_rbi)
      plan_subscription = create :billing_plan_subscription, :zuora, user: user

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assert_difference "Billing::ManualDunningPeriod.count", 1 do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
    end

    test "dunning period gets created for positive balance for RBI Business" do
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription

      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => 8.99 } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)

      fake_zuora_object_account = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account, metrics: { balance: 8.99 }))
      )
      Customer.any_instance.stubs(:zuora_object_account).returns(fake_zuora_object_account)

      customer = @business.customer
      customer.update(auto_pay_reasons: [:india_rbi].to_set)
      assert_predicate @business, :autopay_disabled_by_india_rbi?

      plan_subscription = @business.plan_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assert_difference "Billing::ManualDunningPeriod.count", 1 do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
    end

    test "tracks stats for user account trade controls related invoices" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @user.customer.update auto_pay_reasons: Set[:trade_controls]

      # Generate a positive amount invoice webhook
      invoice_data = stub_zuora_get_invoice(balance: 8.99, amount: 8.99)
      stub_zuora_subscription

      zuora_webhook = build :zuora_webhook, :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        }

      second_zuora_webhook = zuora_webhook.dup

      zuora_webhook.perform

      assert_predicate zuora_webhook, :processed?
      assert_equal 1,
        GitHub.dogstats.increments("trade_controls.invoice_posted", tags: ["positive:true"]).count

      # Generate a zero charge invoice webhook
      stub_zuora_get_invoice(
        id: invoice_data[:id],
        invoiceNumber: invoice_data[:invoiceNumber],
        balance: 0,
        amount: 0
      )

      second_zuora_webhook.perform

      assert_predicate second_zuora_webhook, :processed?
      assert_equal 1,
        GitHub.dogstats.increments("trade_controls.invoice_posted", tags: ["positive:false"]).count
    end

    test "tracks stats for business account trade controls related invoices" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      @business.customer.update auto_pay_reasons: Set[:trade_controls]

      # Generate a positive amount invoice webhook
      invoice_data = stub_zuora_get_invoice \
        balance: 8.99,
        amount: 8.99
      stub_zuora_subscription(plan_subscription: @business_plan_subscription)

      zuora_webhook = build :zuora_webhook, :invoice_posted,
        account_id: @business_plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @business_plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        }
      second_zuora_webhook = zuora_webhook.dup

      zuora_webhook.perform

      assert_predicate zuora_webhook, :processed?
      assert_equal 1,
        GitHub.dogstats.increments("trade_controls.invoice_posted", tags: ["positive:true"]).count

      # Generate a zero charge invoice webhook
      stub_zuora_get_invoice \
        id: invoice_data[:id],
        invoiceNumber: invoice_data[:invoiceNumber],
        balance: 0,
        amount: 0

      second_zuora_webhook.perform

      assert_predicate second_zuora_webhook, :processed?
      assert_equal 1,
        GitHub.dogstats.increments("trade_controls.invoice_posted", tags: ["positive:false"]).count
    end

    test "triggers zuora sync for org with zero dollar fee charge" do
      sponsorship_amount_in_dollars = @org_sponsorship.amount.dollars

      # Generate a positive amount invoice webhook
      invoice_data = stub_zuora_get_invoice \
        balance: sponsorship_amount_in_dollars,
        amount: sponsorship_amount_in_dollars
      stub_zuora_subscription(plan_subscription: @org_plan_subscription)

      zuora_webhook = build :zuora_webhook, :invoice_posted,
        account_id: @org_plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @org_plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        }

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => sponsorship_amount_in_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship_amount_in_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: @org_sponsorship.tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 0.0,
          "chargeName" => "charge-name fee",
          "chargeAmount" => 0.0,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: @org_sponsorship.tier),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      expected_log = {
        "Body": "Adding sponsors fees",
        "gh.user.id": @org.id,
        "gh.billing.zuora.invoice.id": invoice_data[:id],
      }

      assert_logged(**expected_log) do
        assert_enqueued_with(job: SynchronizePlanSubscriptionJob) do
          zuora_webhook.perform
        end
      end

      assert_predicate zuora_webhook, :processed?
      assert_equal 1, GitHub.dogstats.increments("sponsors.fees.added_to_invoice").count
    end

    test "does not trigger zuora sync for org with no zero dollar fee charges" do
      sponsorship_amount_in_dollars = @org_sponsorship.amount.dollars

      # Generate a positive amount invoice webhook
      invoice_data = stub_zuora_get_invoice \
        balance: sponsorship_amount_in_dollars,
        amount: sponsorship_amount_in_dollars
      stub_zuora_subscription(plan_subscription: @org_plan_subscription)

      zuora_webhook = build :zuora_webhook, :invoice_posted,
        account_id: @org_plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => @org_plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        }

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => sponsorship_amount_in_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship_amount_in_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: @org_sponsorship.tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 0.06,
          "chargeName" => "charge-name fee",
          "chargeAmount" => 0.06,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today,
          "serviceEndDate" => GitHub::Billing.today + 1.month,
        }, subscribable: @org_sponsorship.tier),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
      assert_equal 0, GitHub.dogstats.increments("sponsors.fees.added_to_invoice").count
    end

    test "cancels recurring sponsorships from PayPal-using sponsor when positive-balance sponsorship invoice is posted" do
      sponsorship1_dollars = @paypal_sponsorship1.amount.dollars
      invoice_data = stub_zuora_get_invoice(balance: sponsorship1_dollars, amount: sponsorship1_dollars)
      stub_zuora_subscription(plan_subscription: @paypal_sponsor_plan_sub)

      zuora_webhook = build(:zuora_webhook, :invoice_posted,
        account_id: @paypal_sponsor_plan_sub.zuora_account_id,
        payload: {
          "AccountId" => @paypal_sponsor_plan_sub.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => sponsorship1_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship1_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days) + 1.month,
        }, subscribable: @paypal_sponsorship1.tier),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      Billing::Zuora::Webhooks::InvoicePosted.perform(zuora_webhook)

      refute_predicate @paypal_sponsorship1.reload, :active?
      assert_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      refute_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?
      assert_predicate @paypal_one_time_sponsorship.reload, :active?
      refute_predicate @paypal_one_time_sponsorship.reload_subscription_item, :cancelled?
    end

    test "zeroes out sponsors invoice items when the account uses PayPal" do
      freeze_time

      sponsorship1_dollars = @paypal_sponsorship1.amount.dollars
      sponsorship2_dollars = @paypal_sponsorship2.amount.dollars
      total_sponsorship_dollars = sponsorship1_dollars + sponsorship2_dollars
      invoice_data = stub_zuora_get_invoice(
        balance: total_sponsorship_dollars,
        amount: total_sponsorship_dollars
      )
      stub_zuora_subscription
      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => total_sponsorship_dollars } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => sponsorship1_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship1_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days) + 1.month,
        }, subscribable: @paypal_sponsorship1.tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => sponsorship2_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship2_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 10.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 10.days) + 1.month,
        }, subscribable: @paypal_sponsorship2.tier),
      ]

      expected_adjustments = [
        {
          AdjustmentDate: GitHub::Billing.today.to_s,
          Amount: sponsorship1_dollars,
          InvoiceId: invoice_data[:id],
          SourceId: "8675309",
          SourceType: "InvoiceDetail",
          Type: "Credit",
        },
        {
          AdjustmentDate: GitHub::Billing.today.to_s,
          Amount: sponsorship2_dollars,
          InvoiceId: invoice_data[:id],
          SourceId: "myfavoriteid",
          SourceType: "InvoiceDetail",
          Type: "Credit",
        }
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      GitHub.zuorest_client.expects(:create_credit_balance_adjustment).never

      zuora_webhook = build(:zuora_webhook, :invoice_posted,
        account_id: @paypal_sponsor_plan_sub.zuora_account_id,
        payload: {
          "AccountId" => @paypal_sponsor_plan_sub.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      fake_response = [{ "success" => true }, { "success" => true }]
      GitHub.zuorest_client.expects(:create_action).once.with(objects: expected_adjustments,
        type: "InvoiceItemAdjustment").returns(fake_response)

      Billing::Zuora::Webhooks::InvoicePosted.perform(zuora_webhook)

      assert_dogstats_increment("zuora.invoices.zero_out_invoice_items", tags: ["success:true",
        "class:billing/zuora/webhooks/invoice_posted", "includes_sponsors:true"])
      refute_dogstats_increment("zuora.invoices.missed_positive_balance_invoice")
      assert_dogstats_count_value(total_sponsorship_dollars * 100,
        "zuora.invoices.zero_out_line_items.amount_in_cents",
        tags: ["class:billing/zuora/webhooks/invoice_posted", "product:sponsors"])
    end

    test "does not attempt to zero out $0 sponsors invoice items when the account uses PayPal" do
      customer_account = create(:customer_account, :zuora_paypal)
      paypal_sponsor = customer_account.user
      paypal_sponsor_plan_sub = create(:billing_plan_subscription, :zuora, user: paypal_sponsor,
        customer: customer_account.customer)
      tier = create(:sponsors_tier, :published)

      invoice_data = stub_zuora_get_invoice(balance: 5, amount: 5)
      stub_zuora_subscription
      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => 5 } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => 0,
          "chargeName" => "charge-name",
          "chargeAmount" => 0,
          "quantity" => 1.0,
          "serviceStartDate" => GitHub::Billing.today - 3.days,
          "serviceEndDate" => (GitHub::Billing.today - 3.days) + 1.month,
        }, subscribable: tier),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      GitHub.zuorest_client.expects(:create_credit_balance_adjustment).never

      zuora_webhook = build(:zuora_webhook, :invoice_posted,
        account_id: paypal_sponsor_plan_sub.zuora_account_id,
        payload: {
          "AccountId" => paypal_sponsor_plan_sub.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      GitHub.zuorest_client.expects(:create_action).never

      Billing::Zuora::Webhooks::InvoicePosted.perform(zuora_webhook)

      refute_dogstats_increment("zuora.invoices.zero_out_invoice_items")
      refute_dogstats_increment("zuora.invoices.missed_positive_balance_invoice")
    end

    test "logs when zeroing out Sponsors invoice item, due to PayPal deprecation, fails" do
      freeze_time

      sponsorship1_dollars = @paypal_sponsorship1.amount.dollars
      sponsorship2_dollars = @paypal_sponsorship2.amount.dollars
      total_sponsorship_dollars = sponsorship1_dollars + sponsorship2_dollars
      invoice_data = stub_zuora_get_invoice(balance: total_sponsorship_dollars, amount: total_sponsorship_dollars)
      stub_zuora_subscription
      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => total_sponsorship_dollars } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)


      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "8675309",
          "unitPrice" => sponsorship1_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship1_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days) + 1.month,
        }, subscribable: @paypal_sponsorship1.tier),
        Billing::Zuora::SubscribableInvoiceItem.new({
          "id" => "myfavoriteid",
          "unitPrice" => sponsorship2_dollars,
          "chargeName" => "charge-name",
          "chargeAmount" => sponsorship2_dollars,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 10.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 10.days) + 1.month,
        }, subscribable: @paypal_sponsorship2.tier),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      GitHub.zuorest_client.expects(:create_credit_balance_adjustment).never

      zuora_webhook = build(:zuora_webhook, :invoice_posted,
        account_id: @paypal_sponsor_plan_sub.zuora_account_id,
        payload: {
          "AccountId" => @paypal_sponsor_plan_sub.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      expected_adjustments = [
        {
          AdjustmentDate: GitHub::Billing.today.to_s,
          Amount: sponsorship1_dollars,
          InvoiceId: invoice_data[:id],
          SourceId: "8675309",
          SourceType: "InvoiceDetail",
          Type: "Credit",
        },
        {
          AdjustmentDate: GitHub::Billing.today.to_s,
          Amount: sponsorship2_dollars,
          InvoiceId: invoice_data[:id],
          SourceId: "myfavoriteid",
          SourceType: "InvoiceDetail",
          Type: "Credit",
        }
      ]

      fake_response = [{
        "success" => false,
        "reasons" => [{ "message" => "o noes" }],
      }, { "success" => true }]
      GitHub.zuorest_client.expects(:create_action).once.with(objects: expected_adjustments,
        type: "InvoiceItemAdjustment").returns(fake_response)

      assert_logged(
        "code.namespace" => "Billing::Zuora::Webhooks::InvoicePosted",
        "code.function" => "log_failures_to_zero_out_paypal_sponsors_items",
        "gh.user" => @paypal_sponsor.display_login,
        "gh.user.id" => @paypal_sponsor.id,
        "gh.billing.zero_out_paypal_sponsors_items" => "8675309,myfavoriteid",
        "gh.billing.zero_out_paypal_sponsors_items.success_count" => 1,
        "gh.billing.zero_out_paypal_sponsors_items.failure_count" => 1,
        "gh.billing.zero_out_paypal_sponsors_items.zuora_invoice_id" => invoice_data[:id],
        "gh.billing.zero_out_paypal_sponsors_items.total_adjustment_amount_in_dollars" => total_sponsorship_dollars,
        "exception.message" => "o noes",
      ) do
        Billing::Zuora::Webhooks::InvoicePosted.perform(zuora_webhook)
      end

      assert_dogstats_increment("zuora.invoices.zero_out_invoice_items", tags: ["success:false",
        "class:billing/zuora/webhooks/invoice_posted", "includes_sponsors:true"])
      refute_dogstats_increment("zuora.invoices.missed_positive_balance_invoice")
      assert_dogstats_count_value(total_sponsorship_dollars * 100,
        "zuora.invoices.zero_out_line_items.amount_in_cents",
        tags: ["class:billing/zuora/webhooks/invoice_posted", "product:sponsors"])
    end

    test "does not affect non-Sponsors invoice even when a sponsor uses PayPal" do
      non_sponsors_subscribable = create(:marketplace_listing_plan, :verified_listing)
      subscribable_cost = non_sponsors_subscribable.monthly_price_in_dollars
      non_sponsors_sub_item = create(:billing_subscription_item, subscribable: non_sponsors_subscribable, quantity: 1,
        plan_subscription: @paypal_sponsor_plan_sub)

      invoice_data = stub_zuora_get_invoice(balance: subscribable_cost, amount: subscribable_cost)
      stub_zuora_subscription
      fake_zuora_account = Zuorest::Model::Account.new({ "metrics" => { "balance" => subscribable_cost } })
      Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)

      fake_invoice_items = [
        Billing::Zuora::SubscribableInvoiceItem.new({
          "unitPrice" => subscribable_cost,
          "chargeName" => "charge-name",
          "chargeAmount" => subscribable_cost,
          "quantity" => 1.0,
          "serviceStartDate" => SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days,
          "serviceEndDate" => (SponsorsPrimerMailer::PAYPAL_DEPRECATION_DATE - 3.days) + 1.month,
        }, subscribable: non_sponsors_subscribable),
      ]

      Billing::Zuora::Invoice.any_instance.stubs(:invoice_items).returns(fake_invoice_items)

      GitHub.zuorest_client.expects(:create_credit_balance_adjustment).never
      GitHub.zuorest_client.expects(:create_action).never

      zuora_webhook = build(:zuora_webhook, :invoice_posted,
        account_id: @paypal_sponsor_plan_sub.zuora_account_id,
        payload: { "AccountId" => @paypal_sponsor_plan_sub.zuora_account_id, "InvoiceId" => invoice_data[:id] },
      )

      Billing::Zuora::Webhooks::InvoicePosted.perform(zuora_webhook)

      refute_dogstats_increment("zuora.invoices.zero_out_invoice_items")
      refute_dogstats_increment("zuora.invoices.missed_positive_balance_invoice")
      assert_predicate non_sponsors_sub_item.reload, :active?
      assert_predicate @paypal_sponsorship1.reload, :active?
      assert_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_one_time_sponsorship.reload, :active?
    end

    test "schedules a synchronization for all plan subscriptions when the FF is enabled" do
      enable_feature_flag(:billing_schedule_synchronization_after_invoice_posted)

      general_plan_subscription = create(:billing_plan_subscription, :zuora)
      sponsors_plan_subscription = create(:billing_plan_subscription, :zuora,
        user: general_plan_subscription.user,
        purpose: :sponsors,
        zuora_subscription_id: SecureRandom.hex(16),
        zuora_subscription_number: "A-S#{SecureRandom.hex(6)}")
      invoice_data = stub_zuora_get_invoice(balance: 10, amount: 10)
      stub_zuora_subscription(plan_subscription: general_plan_subscription)

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: general_plan_subscription.zuora_account_id,
        payload: {
          "AccountId" => general_plan_subscription.zuora_account_id,
          "InvoiceId" => invoice_data[:id]
        },
      )

      assert_enqueued_jobs(2, only: SynchronizePlanSubscriptionJob)  do
        zuora_webhook.perform
      end

      assert_predicate zuora_webhook, :processed?
    end
  end

  context ".lock_processing" do
    test "ignores webhooks while lock is held" do
      zuora_webhook = build(:zuora_webhook, :invoice_posted, account_id: @plan_subscription.zuora_account_id)
      Billing::Zuora::Webhooks::InvoicePosted.lock_processing(account: @user) do
        zuora_webhook.perform
      end
      assert_predicate zuora_webhook, :ignored?
    end

    test "processes webhooks while lock is held for different account" do
      other_user = create(:user)

      invoice_data = stub_zuora_get_invoice(amount: 0)
      stub_zuora_subscription

      zuora_webhook = build(
        :zuora_webhook,
        :invoice_posted,
        account_id: @plan_subscription.zuora_account_id,
        payload: { "AccountId" => @plan_subscription.zuora_account_id, "InvoiceId" => invoice_data[:id] },
      )

      Billing::Zuora::Webhooks::InvoicePosted.lock_processing(account: other_user) do
        zuora_webhook.perform
      end
      assert_predicate zuora_webhook, :processed?
    end
  end
end if GitHub.billing_enabled?
