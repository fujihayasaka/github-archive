# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class CloseZuoraSubscriptionTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper

    setup do
      synchronize_github_products_to_zuora
    end

    context "without a plan subscription object" do
      test "success when the Zuora subscription has already been cancelled" do
        plan = GitHub::Plan.pro
        user = create(:user, plan: plan)
        zuora_successful_customer_account_creation(user)

        with_live_zuora("zuora/close_out_cancelled_subscription_without_plan_subscription_object") do
          user.reload

          plan_subscription = user.plan_subscription

          Billing::PlanSubscription::Synchronizer.create(plan_subscription)
          plan_subscription = user.plan_subscription.reload


          result = CloseZuoraSubscription.perform(
            zuora_subscription_number: plan_subscription.zuora_subscription_number,
            plan_subscription: nil,
          )

          assert_predicate result, :success?

          zuora_subscription = Billing::Zuora::Subscription.find(plan_subscription.zuora_subscription_number)
          assert_predicate zuora_subscription, :cancelled?

          result = CloseZuoraSubscription.perform(
            zuora_subscription_number: plan_subscription.zuora_subscription_number,
            plan_subscription: nil,
          )

          assert_predicate result, :success?

          zuora_subscription = Billing::Zuora::Subscription.find(plan_subscription.zuora_subscription_number)
          assert_predicate zuora_subscription, :cancelled?
        end
      end

      test "cancels the Zuora subscription" do
        # Normally a PlanSubscription object would be passed but in the case of deletes
        # the object would not be available
        plan = GitHub::Plan.pro
        user = create(:user, plan: plan)
        zuora_successful_customer_account_creation(user)

        with_live_zuora("zuora/close_subscription_without_plan_subscription_object") do
          user.reload

          plan_subscription = user.plan_subscription

          Billing::PlanSubscription::Synchronizer.create(plan_subscription)
          plan_subscription = user.plan_subscription.reload

          result = CloseZuoraSubscription.perform(
            zuora_subscription_number: plan_subscription.zuora_subscription_number,
            plan_subscription: nil,
          )

          assert_predicate result, :success?

          zuora_subscription = Billing::Zuora::Subscription.find(plan_subscription.zuora_subscription_number)
          assert_predicate zuora_subscription, :cancelled?
        end
      end
    end

    test "performs successfully when no Zuora subscription exists" do
      plan_subscription = create(:billing_plan_subscription)
      zuora_successful_customer_account_creation(plan_subscription.user)

      result = CloseZuoraSubscription.perform(
        zuora_subscription_number: plan_subscription.zuora_subscription_number,
        plan_subscription: plan_subscription,
      )

      assert_predicate result, :success?
    end

    test "cancels Zuora subscription" do
      plan = GitHub::Plan.pro
      user = create(:user, plan: plan)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/close_zuora_subscription") do
        user.reload

        plan_subscription = user.plan_subscription

        Billing::PlanSubscription::Synchronizer.create(plan_subscription)
        plan_subscription = user.plan_subscription.reload

        zuora_subscription = plan_subscription.reload.zuora_subscription

        result = CloseZuoraSubscription.perform(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: user.plan_subscription,
        )

        assert_predicate result, :success?

        zuora_subscription = Billing::Zuora::Subscription.find(zuora_subscription.id)
        refute_predicate zuora_subscription, :active?
      end
    end

    test "cancels a suspended Zuora subscription" do
      plan = GitHub::Plan.pro
      user = create(:user, plan: plan)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/close_suspended_zuora_subscription") do
        user.reload

        plan_subscription = user.plan_subscription

        Billing::PlanSubscription::Synchronizer.create(plan_subscription)
        plan_subscription = user.plan_subscription.reload
        plan_subscription.suspend

        zuora_subscription = plan_subscription.reload.zuora_subscription
        assert_predicate plan_subscription.zuora_subscription, :suspended?

        result = CloseZuoraSubscription.perform(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: user.plan_subscription,
        )

        assert_predicate result, :success?
        assert_nil plan_subscription.zuora_subscription
      end
    end

    test "closes out all open invoice balances" do
      plan = GitHub::Plan.pro
      user = create(:user, plan: plan)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/close_zuora_subscription_with_invoices") do
        user.reload

        plan_subscription = user.plan_subscription

        Billing::PlanSubscription::Synchronizer.create(plan_subscription)
        plan_subscription = user.plan_subscription.reload

        zuora_subscription = plan_subscription.reload.zuora_subscription

        create(:asset_status, owner: user, asset_packs: 1)
        Billing::PlanSubscription::Synchronizer.update(plan_subscription.reload)

        invoices = Billing::Zuora::Invoice.invoices_for_subscription(zuora_subscription.number)

        assert_equal 2, invoices.length

        result = CloseZuoraSubscription.perform(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: plan_subscription,
        )

        assert_predicate result, :success?

        invoices.each do |invoice|
          assert_equal 0, invoice.balance
        end
      end
    end

    test "zero out balance for the plan subscription" do
      user = create(:user, plan: pro_plan)
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/close_zuora_subscription_with_invoices") do
        user.reload

        plan_subscription = user.plan_subscription

        synchronize_billing_for(plan_subscription)

        zuora_subscription = plan_subscription.reload.zuora_subscription

        invoices = Billing::Zuora::Invoice.invoices_for_subscription(zuora_subscription.number)

        plan_subscription.update(balance_in_cents: 100)

        closer = ::Billing::CloseZuoraSubscription.new(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: plan_subscription,
        )

        closer.perform

        assert plan_subscription.balance_in_cents.to_i.zero?
      end
    end

    test "clears manual dunning records" do
      user = create(:user, plan: pro_plan)
      create :manual_dunning_period, user: user
      zuora_successful_customer_account_creation(user)

      with_live_zuora("zuora/close_zuora_subscription_with_invoices") do
        user.reload

        plan_subscription = user.plan_subscription

        synchronize_billing_for(plan_subscription)

        zuora_subscription = plan_subscription.reload.zuora_subscription

        invoices = Billing::Zuora::Invoice.invoices_for_subscription(zuora_subscription.number)

        plan_subscription.update(balance_in_cents: 100)

        closer = ::Billing::CloseZuoraSubscription.new(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: plan_subscription,
        )

        closer.perform

        assert_nil user.reload.manual_dunning_period
      end
    end

    test "collects payment for business when collect_payment set to true" do
      with_live_zuora("zuora/close_zuora_subscription_and_collect_payment_for_business") do
        plan_subscription = create :billing_plan_subscription, :business_owned, :zuora_business
        business = plan_subscription.business
        zuora_successful_customer_account_creation(business)

        Billing::PlanSubscription::Synchronizer.create(plan_subscription)
        plan_subscription = business.plan_subscription.reload
        plan_subscription.update(balance_in_cents: 100)

        result = CloseZuoraSubscription.perform(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: plan_subscription,
          collect_payment: true
        )

        assert_predicate result, :success?
        assert plan_subscription.balance_in_cents.to_i.zero?
      end
    end

    # see https://github.com/github/sponsors/issues/3951
    test "does not clear manual dunning records if closing a subscription for a sponsors-purpose customer" do
      user = create(:user, plan: pro_plan)
      create :manual_dunning_period, user: user
      zuora_successful_customer_account_creation(user)
      user.customer.update!(purpose: :sponsors)

      with_live_zuora("zuora/close_zuora_subscription_with_invoices") do
        refute_nil user.reload.sponsors_customer

        plan_subscription = create(:billing_plan_subscription, :zuora,
          user: user,
          customer: user.sponsors_customer,
          purpose: :sponsors,
        )

        Billing::PlanSubscription::Synchronizer
          .expects(:cancel)
          .with(plan_subscription)
          .returns(GitHub::Billing::Result.success)

        Billing::Zuora::ZeroOutInvoices.expects(:for_subscription)
          .with(plan_subscription.zuora_subscription_number)
          .returns(GitHub::Billing::Result.success)

        closer = ::Billing::CloseZuoraSubscription.new(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          plan_subscription: plan_subscription,
        )

        closer.perform

        assert user.reload.manual_dunning_period
      end
    end

    test "sets user billed_on to nil if the customer has no other external subscriptions" do
      user = create(:credit_card_user, billed_on: GitHub::Billing.today)
      plan_subscription = create(:billing_plan_subscription, :zuora,
        user: user,
        customer: user.customer,
        purpose: :general,
      )
      sponsors_plan_subscription = create(:billing_plan_subscription,
        user: user,
        customer: user.customer,
        purpose: :sponsors,
      )
      closer = ::Billing::CloseZuoraSubscription.new(
        zuora_subscription_number: plan_subscription.zuora_subscription_number,
        plan_subscription: plan_subscription,
      )
      closer.expects(:cancel_subscription).once.returns(GitHub::Billing::Result.success)
      refute_nil user.billed_on

      closer.perform

      assert_nil user.reload.billed_on
    end

    test "does not set user billed_on to nil if the customer has other external subscriptions" do
      user = create(:credit_card_user, billed_on: GitHub::Billing.today)
      plan_subscription = create(:billing_plan_subscription, :zuora,
        user: user,
        customer: user.customer,
        purpose: :general,
      )
      sponsors_plan_subscription = create(:billing_plan_subscription, :zuora,
        user: user,
        customer: user.customer,
        purpose: :sponsors,
      )
      closer = ::Billing::CloseZuoraSubscription.new(
        zuora_subscription_number: plan_subscription.zuora_subscription_number,
        plan_subscription: plan_subscription,
      )
      closer.expects(:cancel_subscription).once.returns(GitHub::Billing::Result.success)
      refute_nil user.billed_on

      closer.perform

      refute_nil user.reload.billed_on
    end

    def pro_plan
      @_pro_plan = GitHub::Plan.pro
    end

    def synchronize_billing_for(subscription)
      Billing::PlanSubscription::Synchronizer.create(subscription)
    end
  end
end
