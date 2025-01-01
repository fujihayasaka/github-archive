# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CreateSponsorsPlanSubscriptionTest < GitHub::TestCase
  fixtures do
    @user = create(:credit_card_user)
    @invoiced_org = create(:invoiced_org, :sponsors_invoiced)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  test "returns an error when the account already has a sponsors-purpose plan subscription" do
    plan_sub = create(:billing_plan_subscription, purpose: :sponsors)
    @user.update(sponsors_plan_subscription: plan_sub)
    @user.reload_sponsors_plan_subscription

    error = assert_no_difference -> { Billing::PlanSubscription.count } do
      assert_raises Billing::CreatePlanSubscription::UnprocessableError do
        Billing::CreateSponsorsPlanSubscription.call(account: @user)
      end
    end

    expected_message = "Could not save subscription: User already has a plan subscription for that purpose"
    assert_equal expected_message, error.message
  end

  test "creates a sponsors-purpose plan subscription for general-purpose customer" do
    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreateSponsorsPlanSubscription.call(account: @user)
    end

    refute_nil @user.sponsors_plan_subscription
    assert_equal plan_sub.customer_id, @user.customer.id
    assert_predicate plan_sub, :billable_user?
    assert_equal @user, plan_sub.billable_entity
    assert_predicate plan_sub, :sponsors_purpose?
  end

  test "creates a sponsors-purpose plan subscription for general-purpose customer on enterprise" do
    enterprise = create(:business, :with_credit_card, owners: [@user])
    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreateSponsorsPlanSubscription.call(account: enterprise)
    end

    refute_nil enterprise.sponsors_plan_subscription
    assert_equal plan_sub.customer_id, enterprise.customer.id
    assert_predicate plan_sub, :billable_business?
    assert_equal enterprise, plan_sub.billable_entity
    assert_predicate plan_sub, :sponsors_purpose?
  end

  # see https://github.com/github/sponsors/issues/5223
  test "duplicate detection differentiates between business- and user-owned plan subscriptions" do
    shared_id = 1_000_000
    enterprise = create(:business, :with_credit_card, owners: [@user], id: shared_id)
    user = create(:user, id: shared_id)
    user_plan_sub = create(:billing_plan_subscription, user: user, purpose: :sponsors)

    assert_predicate user_plan_sub, :billable_user?

    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreateSponsorsPlanSubscription.call(account: enterprise)
    end

    refute_nil enterprise.sponsors_plan_subscription
    assert_equal plan_sub.customer_id, enterprise.customer.id
    assert_predicate plan_sub, :billable_business?
    assert_equal enterprise, plan_sub.billable_entity
    assert_predicate plan_sub, :sponsors_purpose?
  end

  test "creates a sponsors-purpose plan subscription for sponsors-purpose customer" do
    plan_sub = assert_difference -> { Billing::PlanSubscription.count } do
      Billing::CreateSponsorsPlanSubscription.call(account: @invoiced_org)
    end

    refute_nil @invoiced_org.sponsors_plan_subscription
    assert_equal plan_sub.customer_id, @invoiced_org.sponsors_customer.id
    assert_predicate plan_sub, :sponsors_purpose?
  end

  test "does not enqueue CollectPaymentForUpgradeJob since the subscription item is sponsor-related" do
    assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
      assert_enqueued_jobs(0, only: CollectPaymentForUpgradeJob) do
        Billing::CreateSponsorsPlanSubscription.call(account: @user)
      end
    end
  end

  test "enqueues a synchronization by default" do
    assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
      Billing::CreateSponsorsPlanSubscription.call(account: @invoiced_org)
    end
  end

  test "does not enqueue synchronization when skip_sync is true" do
    assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
      Billing::CreateSponsorsPlanSubscription.call(account: @invoiced_org, skip_sync: true)
    end
  end
end
