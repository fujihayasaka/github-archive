# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::ResetBillingStatusTest < GitHub::BillingTestCase
    include GitHub::BrainTree::TestHelper

    context ".perform" do
      test "sets the billed on date to the given billing date for general-purpose plan subscription" do
        plan_subscription = create(
          :billing_plan_subscription, :zuora,
          balance_in_cents: 1_000,
          user: create(:user, :zuora, billed_on: Date.new(2013, 1, 1))
        )
        user = plan_subscription.user

        next_billing_date = "2015-05-05"

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: next_billing_date

        assert_equal next_billing_date.to_date, user.reload.billed_on
      end

      test "sets the billed on date to the given billing date for sponsors-purpose plan subscription with general-purpose customer" do
        plan_subscription = create(
          :billing_plan_subscription, :zuora,
          balance_in_cents: 1_000,
          purpose: :sponsors,
          user: create(:user, :zuora, billed_on: Date.new(2013, 1, 1))
        )
        user = plan_subscription.user

        next_billing_date = "2015-05-05"

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: next_billing_date

        assert_equal next_billing_date.to_date, user.reload.billed_on
      end

      test "does not set the billed on date to the given billing date for sponsors-purpose customer" do
        plan_subscription = create(
          :billing_plan_subscription, :zuora, :sponsors_invoiced,
          balance_in_cents: 1_000,
          user: create(:user, :zuora, billed_on: Date.new(2013, 1, 1))
        )
        user = plan_subscription.user
        assert_predicate plan_subscription.customer, :sponsors_purpose?

        next_billing_date = "2015-05-05"
        expected_billed_on = user.billed_on

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: next_billing_date

        assert_equal expected_billed_on, user.reload.billed_on
      end

      test "resets the user's billing attempts" do
        plan_subscription = create(
          :billing_plan_subscription, :zuora,
          user: create(:user, :zuora, billing_attempts: 5)
        )
        user = plan_subscription.user

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        assert_equal 0, user.reload.billing_attempts
      end

      test "clears manual dunning if the user no longer has a balance" do
        plan_subscription = create(
          :billing_plan_subscription, :zuora,
          user: create(:user, :zuora, billing_attempts: 5)
        )
        user = plan_subscription.user
        create :manual_dunning_period, user: user

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        assert_nil user.reload.manual_dunning_period
      end

      test "enables the user's account if it has been disabled" do
        FakeZuora.mock
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        user.disable!

        refute user.enabled?

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        assert user.reload.enabled?
      end

      test "does not upgrade (enable) the enterprise's account if it is under an expired trial" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?

        create(:billing_plan_subscription, :business_owned, customer: business.customer)

        business.expire_trial
        business.reload
        assert_predicate business, :trial_expired?
        assert_predicate business, :downgraded_to_free_plan?

        PlanSubscription::ResetBillingStatus.perform \
          business.customer.plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        assert_predicate business.reload, :downgraded_to_free_plan?
      end

      test "does not upgrade (enable) the enterprise account if its trial has been cancelled" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?

        create(:billing_plan_subscription, :business_owned, customer: business.customer)

        business.cancel_trial(owner)
        business.reload
        assert_predicate business, :trial_cancelled?
        assert_predicate business, :downgraded_to_free_plan?

        PlanSubscription::ResetBillingStatus.perform \
          business.customer.plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        assert_predicate business.reload, :downgraded_to_free_plan?
      end

      test "upgrades (enables) the enterprise account if its trial is not expired or cancelled" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        business.downgrade_to_free_plan
        assert_predicate business, :trial?
        assert_predicate business, :downgraded_to_free_plan?

        create(:billing_plan_subscription, :business_owned, customer: business.customer)

        business.reload
        refute_predicate business, :trial_expired?
        refute_predicate business, :trial_cancelled?
        assert_predicate business, :downgraded_to_free_plan?

        PlanSubscription::ResetBillingStatus.perform \
          business.customer.plan_subscription,
          balance: 0,
          next_billing_date: GitHub::Billing.today

        refute_predicate business.reload, :downgraded_to_free_plan?
      end

      test "updates the billing dates for an enterprise account" do
        Timecop.freeze(GitHub::Billing.timezone.local(2023, 1, 12)) do
          business = create(:business)
          create(:billing_plan_subscription, :business_owned, customer: business.customer)
          business.reload
          next_billed = GitHub::Billing.today + 1.year + 1.day
          assert_equal business.billed_on, next_billed

          PlanSubscription::ResetBillingStatus.perform \
            business.customer.plan_subscription,
            balance: 0,
            next_billing_date: next_billed + 1.month

          business.reload
          assert_equal business.billing_term_ends_at.to_date, next_billed + 1.month - 1.day
          assert_equal business.billing_term_ends_on, next_billed + 1.month - 1.day
          assert_equal business.billed_on, next_billed + 1.month
        end
      end

      test "rebuilds the user's Asset Status" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        user = plan_subscription.user
        Asset::Status.create!(owner: user, bandwidth_up: 1.0, bandwidth_down: 10.0)

        perform_enqueued_jobs(only: [RebuildStorageUsageJob]) do
          PlanSubscription::ResetBillingStatus.perform \
            plan_subscription,
            balance: 0,
            next_billing_date: GitHub::Billing.today
        end

        assert_equal 0.0, user.asset_status.reload.bandwidth_up
        assert_equal 0.0, user.asset_status.bandwidth_down
      end

      test "updates the plan_subscription balance for general-purpose plan subscription" do
        plan_subscription = create(:billing_plan_subscription, :zuora, balance_in_cents: 0)
        user = plan_subscription.user

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: -2000,
          next_billing_date: GitHub::Billing.today

        assert_equal -2000, user.plan_subscription.balance_in_cents
      end

      test "updates the plan_subscription balance for sponsors-purpose plan subscription" do
        plan_subscription = create(:billing_plan_subscription, :zuora, :sponsors_invoiced, balance_in_cents: 0)
        user = plan_subscription.user

        PlanSubscription::ResetBillingStatus.perform \
          plan_subscription,
          balance: -2000,
          next_billing_date: GitHub::Billing.today

        assert_equal -2000, user.sponsors_plan_subscription.balance_in_cents
      end
    end
  end
end
