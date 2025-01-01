# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class ResetBillingStatusTest < GitHub::BillingTestCase
    include DogstatsTestHelpers
    include GitHub::BrainTree::TestHelper
    include GitHub::LoggerHelper

    context ".perform" do
      test "sets the billed on date to the given future billing date for general-purpose customer" do
        user = create(:credit_card_user, :zuora, billed_on: GitHub::Billing.today)
        customer = user.customer

        next_billing_date = GitHub::Billing.today + 1.month

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: next_billing_date

        assert_equal next_billing_date, user.reload.billed_on
      end

      test "does not set the billed on date to the given billing date for sponsors-purpose customer" do
        org = create(:credit_card_org, :sponsors_invoiced, billed_on: nil)
        customer = org.sponsors_customer

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today + 1.month

        assert_nil org.reload.billed_on
      end

      test "does not set the billed on date to the past" do
        user = create(:credit_card_user, :zuora, billed_on: nil)
        customer = user.customer

        next_billing_date = GitHub::Billing.today - 1.month

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: next_billing_date

        assert_equal GitHub::Billing.today, user.reload.next_billing_date
      end

      test "does not set the billed on date beyond an existing future date" do
        future_billing_date = (GitHub::Billing.today + 1.month)
        user = create(:credit_card_user, :zuora, billed_on: future_billing_date)
        customer = user.customer

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: future_billing_date + 1.month

        assert_equal future_billing_date, user.reload.billed_on
      end

      test "resets the user's billing attempts" do
        user = create(:credit_card_user, :zuora, billing_attempts: 5)
        customer = user.customer

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        assert_equal 0, user.reload.billing_attempts
      end

      test "clears manual dunning if the user no longer has a balance" do
        user = create(:credit_card_user, :zuora, billing_attempts: 5)
        customer = user.customer
        create :manual_dunning_period, user: user

        assert_predicate user.reload.manual_dunning_period, :present?

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        assert_nil user.reload.manual_dunning_period
      end

      test "enables the user's account if it has been disabled" do
        FakeZuora.mock
        user = create(:credit_card_user, :zuora)
        customer = user.customer
        user.disable!

        refute_predicate user, :enabled?

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        assert user.reload.enabled?
      end

      test "does not upgrade (enable) the enterprise's account if it is under an expired trial" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?

        business.expire_trial
        business.reload
        assert_predicate business, :trial_expired?
        assert_predicate business, :downgraded_to_free_plan?

        ResetBillingStatus.perform \
          business.customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        assert_predicate business.reload, :downgraded_to_free_plan?
      end

      test "does not upgrade (enable) the enterprise account if its trial has been cancelled" do
        owner = create(:user)
        business = create(:business, owners: [owner])
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        assert_predicate business, :trial?

        business.cancel_trial(owner)
        business.reload
        assert_predicate business, :trial_cancelled?
        assert_predicate business, :downgraded_to_free_plan?

        ResetBillingStatus.perform \
          business.customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        assert_predicate business.reload, :downgraded_to_free_plan?
      end

      test "upgrades (enables) the enterprise account if its trial is not expired or cancelled" do
        business = create(:business)
        business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
        business.downgrade_to_free_plan
        assert_predicate business, :trial?
        assert_predicate business, :downgraded_to_free_plan?

        business.reload
        refute_predicate business, :trial_expired?
        refute_predicate business, :trial_cancelled?
        assert_predicate business, :downgraded_to_free_plan?

        ResetBillingStatus.perform \
          business.customer,
          balance_in_cents: 0,
          next_billing_date: GitHub::Billing.today

        refute_predicate business.reload, :downgraded_to_free_plan?
      end

      test "updates the billing dates for an enterprise account" do
        Timecop.freeze(GitHub::Billing.timezone.local(2023, 1, 12)) do
          business = create(:business)
          next_billed = GitHub::Billing.today + 1.year + 1.day
          assert_equal business.billed_on, next_billed

          ResetBillingStatus.perform \
            business.customer,
            balance_in_cents: 0,
            next_billing_date: next_billed - 1.month

          business.reload
          assert_equal business.billing_term_ends_at.to_date, next_billed - 1.month - 1.day
          assert_equal business.billing_term_ends_on, next_billed - 1.month - 1.day
          assert_equal business.billed_on, next_billed - 1.month
        end
      end

      test "rebuilds the user's Asset Status" do
        user = create(:credit_card_user, :zuora)
        customer = user.customer
        Asset::Status.create!(owner: user, bandwidth_up: 1.0, bandwidth_down: 10.0)

        perform_enqueued_jobs(only: [RebuildStorageUsageJob]) do
          ResetBillingStatus.perform \
            customer,
            balance_in_cents: 0,
            next_billing_date: GitHub::Billing.today
        end

        assert_equal 0.0, user.asset_status.reload.bandwidth_up
        assert_equal 0.0, user.asset_status.bandwidth_down
      end

      test "updates the plan_subscription balance for general-purpose customer" do
        sub_item = create(:billing_subscription_item)
        user = sub_item.user
        customer = user.customer

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: -2000,
          next_billing_date: GitHub::Billing.today

        assert_equal -2000, user.plan_subscription.balance_in_cents
      end

      test "updates the plan_subscription balance for sponsors-purpose customer" do
        org = create(:credit_card_org, :sponsors_invoiced)
        sponsors_item = create(:sponsors_subscription_item, account: org)
        customer = org.sponsors_customer

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: -2000,
          next_billing_date: GitHub::Billing.today

        assert_equal -2000, org.sponsors_plan_subscription.balance_in_cents
      end

      test "updates all plan_subscription balances for a customer when feature enabled" do
        sub_item = create(:billing_subscription_item)
        user = sub_item.user
        create(:sponsors_subscription_item, account: user)
        customer = user.customer

        assert_equal 2, customer.plan_subscriptions.count

        ResetBillingStatus.perform \
          customer,
          balance_in_cents: -2000,
          next_billing_date: GitHub::Billing.today

        assert_equal -2000, user.plan_subscription.balance_in_cents
        assert_equal -2000, user.sponsors_plan_subscription.balance_in_cents
      end

      test "records missing billable entity" do
        customer = create(:customer)

        assert_nil customer.billable_owner

        logs = capture_logs do
          ResetBillingStatus.perform \
            customer,
            balance_in_cents: 0,
            next_billing_date: GitHub::Billing.today
        end

        assert_match "Missing billable entity for customer", logs
        assert_match "customer.id=\"#{customer.id}\"", logs

        assert_dogstats_increment 1, "billing.reset_billing_status.missing_billable_entity"
      end
    end
  end
end
