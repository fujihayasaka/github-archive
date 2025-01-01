# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CreatePlanSubscriptionTest < GitHub::TestCase
  fixtures do
    @user = create(:credit_card_user)
    @org = create(:organization, :invoiced, :zuora)
  end

  setup do
    skip unless GitHub.billing_enabled?
  end

  test "returns an error when the account already has a general-purpose plan subscription" do
    plan_sub = create(:billing_plan_subscription, purpose: :general)
    @user.update(plan_subscription: plan_sub)
    @user.reload_plan_subscription

    error = assert_no_difference -> { Billing::PlanSubscription.count } do
      assert_raises Billing::CreatePlanSubscription::UnprocessableError do
        Billing::CreatePlanSubscription.call(account: @user)
      end
    end

    expected_message = "Could not save subscription: User already has a plan subscription for that purpose"
    assert_equal expected_message, error.message
  end

  test "creates a general-purpose plan subscription for an individual" do
    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreatePlanSubscription.call(account: @user)
    end

    refute_nil @user.plan_subscription
    assert_equal plan_sub.customer_id, @user.customer.id
    assert_predicate plan_sub, :general_purpose?
  end

  test "creates a general-purpose plan subscription for an organization" do
    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreatePlanSubscription.call(account: @org)
    end

    refute_nil @org.plan_subscription
    assert_equal plan_sub.customer_id, @org.customer.id
    assert_predicate plan_sub, :general_purpose?
  end

  test "enqueues a synchronization by default" do
    assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
      Billing::CreatePlanSubscription.call(account: @org)
    end
  end

  test "does not enqueue synchronization when skip_sync is true" do
    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      Billing::CreatePlanSubscription.call(account: @org, skip_sync: true)
    end
  end
end
