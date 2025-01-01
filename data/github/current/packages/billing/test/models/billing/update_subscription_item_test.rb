# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingUpdateSubscriptionItemTest < GitHub::TestCase
  include GitHub::BillingTest
  include PlatformTestHelpers::InterfaceHelpers
  include HookIntegrationTestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @business = create(:business, :with_self_serve_payment)
    @business_owner_org_admin = @business.owners.first
    @business_org = create :organization, business: @business, admin: @business_owner_org_admin
    @business_plan_subscription = create(:billing_plan_subscription, :business_owned, customer: @business.customer)
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    GitHub::Experiment.raise_on_mismatches = false
    synchronize_github_products_to_zuora
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  test "ends all free trials when switching to a non free trial plan" do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    plan_subscription = create :billing_plan_subscription, :zuora
    user = plan_subscription.user

    free_trial_1 = create(:marketplace_listing_plan, :free_trial)
    listing = free_trial_1.listing
    free_trial_2 = create(:marketplace_listing_plan, :free_trial, listing: listing)
    paid_plan    = create(:marketplace_listing_plan, :verified_listing, listing: listing)

    subscription_item = create(:billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: free_trial_1,
      quantity: 1)

    Billing::SubscriptionItemUpdater.perform(
      subscribable: free_trial_1,
      quantity: 1,
      sender: user,
      start_free_trial: true,
      plan_subscription: plan_subscription,
    )

    result = assert_no_difference ["Billing::SubscriptionItem.active.count", "Billing::PendingSubscriptionItemChange.count"] do
      Billing::UpdateSubscriptionItem.call(
        subscribable: free_trial_2,
        quantity: 1,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end

    pending_item_change = user.reload.pending_subscription_item_changes.first
    result_subscription_item = result.subscription_item
    refute_equal subscription_item.global_relay_id, result_subscription_item.id
    assert_equal 1, result_subscription_item.quantity
    assert result_subscription_item.on_free_trial?
    assert_equal free_trial_2, pending_item_change.subscribable

    # ensure we're on free trial after transfer
    subscription_item.reload
    new_subscription_item = user.subscription_items.active.last
    refute_equal subscription_item.id, new_subscription_item.id
    assert subscription_item.cancelled?
    refute new_subscription_item.cancelled?
    assert subscription_item.on_free_trial?
    assert new_subscription_item.on_free_trial?

    assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
      Billing::UpdateSubscriptionItem.call(
        subscribable: paid_plan,
        quantity: 1,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end

    subscription_item.reload
    new_subscription_item.reload
    paid_subscription_item = user.subscription_items.active.last

    refute paid_subscription_item.on_free_trial?
    refute new_subscription_item.on_free_trial?
    refute subscription_item.on_free_trial?
  end

  test "transfers a free trial when changing plans with free trials" do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
    plan_subscription = create :billing_plan_subscription, :zuora
    user = plan_subscription.user

    old_listing_plan = create(:marketplace_listing_plan, :free_trial)
    new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

    subscription_item = create(:billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1)

    Billing::SubscriptionItemUpdater.perform(
      subscribable: old_listing_plan,
      quantity: 1,
      sender: user,
      start_free_trial: true,
      plan_subscription: plan_subscription,
    )

    result = assert_no_difference ["Billing::SubscriptionItem.active.count",
                          "Billing::PendingSubscriptionItemChange.count"] do
      Billing::UpdateSubscriptionItem.call(
        subscribable: new_listing_plan,
        quantity: 1,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end

    pending_item_change = user.reload.pending_subscription_item_changes.first
    refute_equal subscription_item.global_relay_id, result.subscription_item.id
    assert_equal 1, result.subscription_item.quantity
    assert result.subscription_item.on_free_trial?
    assert_equal new_listing_plan.listing.name,
      result.subscription_item.subscribable.listing.name
    assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
    assert_equal new_listing_plan, pending_item_change.subscribable
  end

  test "creates a free trial when changing between free and free trial plans" do
    plan_subscription = create(:billing_plan_subscription)
    user = plan_subscription.user
    old_listing_plan = create(:marketplace_listing_plan, :free)
    new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

    subscription_item = create(:billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1)

    result = assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
      Billing::UpdateSubscriptionItem.call(
        subscribable: new_listing_plan,
        quantity: 1,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end

    pending_item_change = user.reload.pending_subscription_item_changes.first
    refute_equal subscription_item.global_relay_id, result.subscription_item.id
    assert_equal 1, result.subscription_item.quantity
    assert result.subscription_item.on_free_trial?
    assert_equal new_listing_plan.listing.name,
      result.subscription_item.subscribable.listing.name
    assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
    assert_equal new_listing_plan, pending_item_change.subscribable
  end

  test "does not create a free trial when changing between paid and free trial plans" do
    plan_subscription = create(:billing_plan_subscription)
    user = plan_subscription.user
    old_listing_plan = create(:marketplace_listing_plan, :paid, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

    subscription_item = create(:billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1)

    result = assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
      Billing::UpdateSubscriptionItem.call(
        subscribable: new_listing_plan,
        quantity: 1,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end

    refute_equal subscription_item.global_relay_id, result.subscription_item.id
    assert_equal 1, result.subscription_item.quantity
    refute result.subscription_item.on_free_trial?
    assert_equal new_listing_plan.listing.name,
      result.subscription_item.subscribable.listing.name
    assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
  end

  test "updates a subscription item for the specified account's subscription" do
    user = create(:user)
    org = create(:credit_card_org, admin: user)
    plan_subscription = create(:billing_plan_subscription, user: org)

    old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 3,
          viewer: user,
          plan_subscription: plan_subscription,
        )
        assert_equal 3, result.subscription_item.quantity
        assert_equal new_listing_plan.listing.name,
          result.subscription_item.subscribable.listing.name
        assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: org.id, plan_name: org.plan.name, purpose: plan_subscription.purpose,
    }, user: org])
  end

  test "updates the quantity on sponsor items" do
    sponsor_item = create(:sponsorship).subscription_item
    sponsor = sponsor_item.plan_subscription.user
    sponsors_tier = sponsor_item.subscribable
    plan_subscription = sponsor_item.plan_subscription

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(
          subscribable: sponsors_tier,
          quantity: 3,
          viewer: sponsor,
          plan_subscription: sponsor_item.plan_subscription,
        )
        assert_equal 3, result.subscription_item.quantity
        assert_equal sponsors_tier.listing.name,
          result.subscription_item.subscribable.listing.name
        assert_equal sponsors_tier.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: sponsor.id, plan_name: sponsor.plan.name, purpose: plan_subscription.purpose,
    }, user: sponsor])
  end

  test "updates a subscription item when only changing the quantity" do
    user = create(:user)
    org = create(:credit_card_org, admin: user)
    plan_subscription = create(:billing_plan_subscription, user: org)

    listing_plan = create(:marketplace_listing_plan, :verified_listing)

    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: listing_plan,
      quantity: 1

    inputs = {
      subscribable: listing_plan,
      quantity: 3,
      viewer: user,
      plan_subscription: plan_subscription,
    }

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(**inputs)

        assert_equal 3, result.subscription_item.quantity
        assert_equal listing_plan.listing.name, result.subscription_item.subscribable.listing.name
        assert_equal listing_plan.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: org.id, plan_name: org.plan.name, purpose: plan_subscription.purpose,
    }, user: org])
  end

  test "updates a subscription item for the specified account's subscription, dealing with old 0-quantity subscription items" do
    user = create(:user)
    org = create(:credit_card_org, admin: user)
    plan_subscription = create(:billing_plan_subscription, user: org)

    old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1

    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: new_listing_plan,
      quantity: 0

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 3,
          viewer: user,
          plan_subscription: plan_subscription,
        )
        assert_equal 3, result.subscription_item.quantity
        assert_equal new_listing_plan.listing.name, result.subscription_item.subscribable.listing.name
        assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: org.id, plan_name: org.plan.name, purpose: plan_subscription.purpose,
    }, user: org])
  end

  test "refuses to update a subscription item for the another account's subscription" do
    user = create(:user)
    org = create :credit_card_org # user is not an admin
    plan_subscription = create(:billing_plan_subscription, user: org)

    old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

    subscription_item = create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1

    assert_performed_jobs(0, only: SynchronizePlanSubscriptionJob) do
      error = assert_raises Billing::UpdateSubscriptionItem::ForbiddenError do
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 3,
          viewer: user,
          plan_subscription: plan_subscription,
        )
      end

      assert_equal "#{user} does not have permission to manage this account (#{org.login})", error.message
    end

    subscription_item.reload
    assert_equal old_listing_plan, subscription_item.subscribable
  end

  test "refuses to update a subscription item for an unknown account" do
    org = create(:credit_card_org)
    org_admin = org.admins.first
    marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    plan_subscription = create(:billing_plan_subscription, user: org)
    org.delete
    assert_performed_jobs(0, only: SynchronizePlanSubscriptionJob) do
      error = assert_raises Billing::UpdateSubscriptionItem::UnprocessableError do
        Billing::UpdateSubscriptionItem.call(
          subscribable: marketplace_listing_plan,
          quantity: 2,
          viewer: org_admin,
          plan_subscription: plan_subscription,
        )
      end

      assert_equal "Account not found", error.message
    end
  end

  test "sends a marketplace subscription changed event" do
    user = create :credit_card_user, plan_subscription: create(:billing_plan_subscription)

    old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

    item = create :billing_subscription_item,
      plan_subscription: user.plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1

    hook = create :hook, :web,
      installation_target: old_listing_plan.listing,
      events: %w(marketplace_purchase)
    deliveries = subscribe_to_hook_delivery "marketplace_purchase"

    Billing::UpdateSubscriptionItem.call(
      subscribable: new_listing_plan,
      quantity: 3,
      viewer: user,
      plan_subscription: item.plan_subscription,
    )

    assert_equal 1, deliveries.count
    assert_includes deliveries.hooks, hook

    payload = deliveries.payload_for_hook(hook)
    assert_equal "changed", payload[:action]

    purchase = payload[:marketplace_purchase]
    assert_equal new_listing_plan.id, purchase[:plan][:id]
    assert_equal 3, purchase[:unit_count]

    previous_purchase = payload[:previous_marketplace_purchase]
    assert_equal old_listing_plan.id, previous_purchase[:plan][:id]
    assert_equal 1, previous_purchase[:unit_count]
  end

  test "does not disclose account payment status to unauthorized accounts" do # #73466
    account = create(:user)
    unauthorized = create(:user)
    plan_subscription = create(:billing_plan_subscription, user: account)
    marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    create(:billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: marketplace_listing_plan,
      quantity: 1,
    )

    error = assert_raises Billing::UpdateSubscriptionItem::ForbiddenError do
      Billing::UpdateSubscriptionItem.call(
        subscribable: marketplace_listing_plan,
        quantity: 3,
        viewer: unauthorized,
        plan_subscription: plan_subscription,
      )
    end
    assert_equal "#{unauthorized} does not have permission to manage this account (#{account})", error.message
  end

  test "raises an error for users without a valid payment method" do
    user = create(:user)
    plan_subscription = create :billing_plan_subscription, user: user
    marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: marketplace_listing_plan,
      quantity: 1

    error = assert_raises Billing::UpdateSubscriptionItem::UnprocessableError do
      Billing::UpdateSubscriptionItem.call(
        subscribable: marketplace_listing_plan,
        quantity: 3,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end
    assert_equal "Please add a payment method before checking out.", error.message
  end

  test "returns an error for invoiced orgs attempting to change to paid plans" do
    user = create(:user)
    org = create(:invoiced_org, admin: user)
    plan_subscription = create :billing_plan_subscription, user: org
    original_marketplace_listing_plan = create(:marketplace_listing_plan, :free, :verified_listing)
    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: original_marketplace_listing_plan,
      quantity: 1
    new_paid_marketplace_listing_plan = create(:marketplace_listing_plan, :paid, listing: original_marketplace_listing_plan.listing)

    error = assert_raises Billing::UpdateSubscriptionItem::UnprocessableError do
      Billing::UpdateSubscriptionItem.call(
        subscribable: new_paid_marketplace_listing_plan,
        quantity: 3,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end
    assert_equal "Invoiced customers cannot purchase paid Marketplace plans at this time. Please contact support if you have any questions.", error.message
  end

  test "updates a subscription item for a Sponsors invoiced customer" do
    user = create(:user)
    org = create(:invoiced_org, :sponsors_invoiced, admin: user)
    sponsors_plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced, user: org)
    old_sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    new_sponsors_tier = create(:sponsors_tier, :published, sponsors_listing: old_sponsors_tier.sponsors_listing)
    item = create(:sponsors_subscription_item,
      plan_subscription: sponsors_plan_subscription,
      subscribable: old_sponsors_tier,
      quantity: 1
    )

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(
          subscribable: new_sponsors_tier,
          quantity: 1,
          viewer: user,
          plan_subscription: item.plan_subscription,
        )
        assert_equal 1, result.subscription_item.quantity
        assert_equal new_sponsors_tier.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: org.id, plan_name: org.plan.name, purpose: sponsors_plan_subscription.purpose,
    }, user: org])
  end

  test "updates a subscription item for invoiced orgs changing to a free plan" do
    user = create(:user)
    org = create(:invoiced_org, admin: user)
    plan_subscription = create :billing_plan_subscription, user: org
    original_marketplace_listing_plan = create(:marketplace_listing_plan, :free, :verified_listing)
    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: original_marketplace_listing_plan,
      quantity: 1
    new_free_marketplace_listing_plan = create(:marketplace_listing_plan, :free, listing: original_marketplace_listing_plan.listing)

    assert_no_difference "Billing::SubscriptionItem.active.count" do
      assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
        result = Billing::UpdateSubscriptionItem.call(
          subscribable: new_free_marketplace_listing_plan,
          quantity: 3,
          viewer: user,
          plan_subscription: plan_subscription,
        )
        assert_equal 3, result.subscription_item.quantity
        assert_equal new_free_marketplace_listing_plan.name, result.subscription_item.subscribable.name
      end
    end

    assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
      user_id: org.id, plan_name: org.plan.name, purpose: plan_subscription.purpose,
    }, user: org])
  end

  test "does not update subscription item for billing manager of an organization" do
    user = create(:user)
    org = create(:credit_card_org)
    org.billing.add_manager(user, actor: org.admins.first)
    marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    plan_subscription = create(:billing_plan_subscription, user: org)
    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: marketplace_listing_plan,
      quantity: 1

    error = assert_raises Billing::UpdateSubscriptionItem::ForbiddenError do
      Billing::UpdateSubscriptionItem.call(
        subscribable: marketplace_listing_plan,
        quantity: 2,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end
    assert_equal "#{user} does not have permission to manage this account (#{org})", error.message
  end

  test "requires a quantity greater than zero" do
    user = create :credit_card_user
    plan_subscription = create :billing_plan_subscription, user: user

    old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

    create :billing_subscription_item,
      plan_subscription: plan_subscription,
      subscribable: old_listing_plan,
      quantity: 1

    error = assert_raises Billing::UpdateSubscriptionItem::UnprocessableError do
      Billing::UpdateSubscriptionItem.call(
        subscribable: new_listing_plan,
        quantity: 0,
        viewer: user,
        plan_subscription: plan_subscription,
      )
    end
    assert_equal "Quantity must be greater than 0.", error.message
  end

  test "whitelists the listing's oauth application if grantOap is specified" do
    user = create(:user)
    org = create(:organization, :zuora, admin: user)
    org.enable_oauth_application_restrictions
    plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
    marketplace_listing_plan = create(:marketplace_listing_plan, :verified_listing)
    create(:billing_subscription_item, plan_subscription: plan_subscription, subscribable: marketplace_listing_plan, quantity: 1)
    oauth_app = marketplace_listing_plan.listing.listable

    refute org.allows_oauth_application?(oauth_app)

    Billing::UpdateSubscriptionItem.call(
      subscribable: marketplace_listing_plan,
      quantity: 1,
      grant_oap: true,
      viewer: user,
      plan_subscription: plan_subscription,
      installation_account: org,
    )

    assert org.allows_oauth_application?(oauth_app)
  end

  context "sponsors tiers" do
    test "updates a sponsor's subscription item to a new tier" do
      old_tier = create(:sponsors_tier, :approved_sponsors_listing)
      new_tier = create(:sponsors_tier, :published, sponsors_listing: old_tier.sponsors_listing)

      sponsorship = create(:sponsorship, tier: old_tier)
      user = sponsorship.sponsor
      plan_subscription = sponsorship.plan_subscription

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::UpdateSubscriptionItem.call(
            subscribable: new_tier,
            quantity: 3,
            viewer: user,
            plan_subscription: plan_subscription,
          )

          subscription_item = result.subscription_item
          assert_equal 3, subscription_item.quantity
          assert_equal new_tier.listing.name, subscription_item.subscribable.listing.name
          assert_equal new_tier.name, subscription_item.subscribable_name
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        user_id: user.id, plan_name: user.plan.name, purpose: plan_subscription.purpose,
      }, user: user])
    end

    test "updates a sponsor's subscription item when only changing the quantity" do
      tier = create(:sponsors_tier, :approved_sponsors_listing)
      sponsorship = create(:sponsorship, tier: tier)
      user = sponsorship.sponsor
      plan_subscription = sponsorship.plan_subscription

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::UpdateSubscriptionItem.call(
            subscribable: tier,
            quantity: 3,
            viewer: user,
            plan_subscription: plan_subscription,
          )

          subscription_item = result.subscription_item
          assert_equal 3, subscription_item.quantity
          assert_equal tier.listing.name, subscription_item.subscribable.listing.name
          assert_equal tier.name, subscription_item.subscribable_name
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        user_id: user.id, plan_name: user.plan.name, purpose: plan_subscription.purpose,
      }, user: user])
    end
  end

  context "self-serve payment enterprise account orgs" do
    test "ends all free trials when switching to a non free trial plan" do
      self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      free_trial_1 = create(:marketplace_listing_plan, :free_trial)
      listing = free_trial_1.listing
      free_trial_2 = create(:marketplace_listing_plan, :free_trial, listing: listing)
      paid_plan    = create(:marketplace_listing_plan, :verified_listing, listing: listing)

      subscription_item = create(:billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: free_trial_1,
        quantity: 1,
        organization: @business_org,
      )

      Billing::SubscriptionItemUpdater.perform(
        subscribable: free_trial_1,
        quantity: 1,
        sender: @business_owner_org_admin,
        start_free_trial: true,
        plan_subscription: @business_plan_subscription,
        organization: @business_org
      )

      result = assert_no_difference ["Billing::SubscriptionItem.active.count",
                            "Billing::PendingSubscriptionItemChange.count"] do
        Billing::UpdateSubscriptionItem.call(
          subscribable: free_trial_2,
          quantity: 1,
          viewer: @business_owner_org_admin,
          plan_subscription: @business_plan_subscription,
          installation_account: @business_org,
        )
      end

      pending_item_change = @business.customer.reload.pending_subscription_item_changes.first
      result_subscription_item = result.subscription_item
      refute_equal subscription_item.global_relay_id, result_subscription_item.id
      assert_equal 1, result_subscription_item.quantity
      assert result_subscription_item.on_free_trial?
      assert_equal free_trial_2, pending_item_change.subscribable

      # ensure we're on free trial after transfer
      subscription_item.reload
      new_subscription_item = @business_plan_subscription.subscription_items.active.last
      refute_equal subscription_item.id, new_subscription_item.id
      assert subscription_item.cancelled?
      refute new_subscription_item.cancelled?
      assert subscription_item.on_free_trial?
      assert new_subscription_item.on_free_trial?

      assert_difference "Billing::PendingSubscriptionItemChange.count", -1 do
        Billing::UpdateSubscriptionItem.call(
          subscribable: paid_plan,
          quantity: 1,
          viewer: @business_owner_org_admin,
          plan_subscription: @business_plan_subscription,
          installation_account: @business_org,
        )
      end

      subscription_item.reload
      new_subscription_item.reload
      paid_subscription_item = @business_plan_subscription.subscription_items.active.last

      refute paid_subscription_item.on_free_trial?
      refute new_subscription_item.on_free_trial?
      refute subscription_item.on_free_trial?
    end

    test "transfers a free trial when changing plans with free trials" do
      self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      old_listing_plan = create(:marketplace_listing_plan, :free_trial)
      new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

      subscription_item = create(:billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org,
      )

      Billing::SubscriptionItemUpdater.perform(
        subscribable: old_listing_plan,
        quantity: 1,
        sender: @business_owner_org_admin,
        start_free_trial: true,
        plan_subscription: @business_plan_subscription,
        organization: @business_org
      )

      result = assert_no_difference ["Billing::SubscriptionItem.active.count",
                            "Billing::PendingSubscriptionItemChange.count"] do
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 1,
          viewer: @business_owner_org_admin,
          plan_subscription: @business_plan_subscription,
          installation_account: @business_org,
        )
      end

      pending_item_change = @business.customer.reload.pending_subscription_item_changes.first
      refute_equal subscription_item.global_relay_id, result.subscription_item.id
      assert_equal 1, result.subscription_item.quantity
      assert result.subscription_item.on_free_trial?
      assert_equal new_listing_plan.listing.name,
        result.subscription_item.subscribable.listing.name
      assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
      assert_equal new_listing_plan, pending_item_change.subscribable
    end

    test "must have permission to apply update" do
      old_listing_plan = create(:marketplace_listing_plan, :free)
      new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)
      random_org = create(:organization)

      create(:billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: random_org,
      )

      assert_raises Billing::UpdateSubscriptionItem::ForbiddenError do
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 1,
          viewer: create(:user),
          plan_subscription: @business_plan_subscription,
          installation_account: random_org,
        )
      end
    end

    test "creates a free trial when changing between free and free trial plans" do
      old_listing_plan = create(:marketplace_listing_plan, :free)
      new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

      subscription_item = create(:billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org,
      )

      result = assert_difference "Billing::PendingSubscriptionItemChange.count", 1 do
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 1,
          viewer: @business_owner_org_admin,
          plan_subscription: @business_plan_subscription,
          installation_account: @business_org,
        )
      end

      pending_item_change = @business.customer.reload.pending_subscription_item_changes.first
      refute_equal subscription_item.global_relay_id, result.subscription_item.id
      assert_equal 1, result.subscription_item.quantity
      assert_equal @business_org, result.subscription_item.organization
      assert result.subscription_item.on_free_trial?
      assert_equal new_listing_plan.listing.name,
        result.subscription_item.subscribable.listing.name
      assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
      assert_equal new_listing_plan, pending_item_change.subscribable
    end

    test "does not create a free trial when changing between paid and free trial plans" do
      old_listing_plan = create(:marketplace_listing_plan, :paid, :verified_listing)
      new_listing_plan = create(:marketplace_listing_plan, :free_trial, listing: old_listing_plan.listing)

      subscription_item = create(:billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org,
      )

      result = assert_no_difference "Billing::PendingSubscriptionItemChange.count" do
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_listing_plan,
          quantity: 1,
          viewer: @business_owner_org_admin,
          plan_subscription: @business_plan_subscription,
          installation_account: @business_org,
        )
      end

      refute_equal subscription_item.global_relay_id, result.subscription_item.id
      assert_equal 1, result.subscription_item.quantity
      assert_equal @business_org, result.subscription_item.organization
      refute result.subscription_item.on_free_trial?
      assert_equal new_listing_plan.listing.name,
        result.subscription_item.subscribable.listing.name
      assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
    end

    test "updates a subscription item for an org admin that is an EA owner" do
      old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

      create :billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::UpdateSubscriptionItem.call(
            subscribable: new_listing_plan,
            quantity: 3,
            viewer: @business_owner_org_admin,
            plan_subscription: @business_plan_subscription,
            installation_account: @business_org
          )
          assert_equal 3, result.subscription_item.quantity
          assert_equal @business_org, result.subscription_item.organization
          assert_equal new_listing_plan.listing.name,
            result.subscription_item.subscribable.listing.name
          assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        business_id: @business.id, plan_name: @business.plan.name, purpose: @business_plan_subscription.purpose,
      }, business: @business])
    end

    test "updates a subscription item when only changing the quantity" do
      listing_plan = create(:marketplace_listing_plan, :verified_listing)

      create :billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: listing_plan,
        quantity: 1,
        organization: @business_org

      inputs = {
        subscribable: listing_plan,
        quantity: 3,
        viewer: @business_owner_org_admin,
        plan_subscription: @business_plan_subscription,
        installation_account: @business_org
      }

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::UpdateSubscriptionItem.call(**inputs)

          assert_equal 3, result.subscription_item.quantity
          assert_equal @business_org, result.subscription_item.organization
          assert_equal listing_plan.listing.name, result.subscription_item.subscribable.listing.name
          assert_equal listing_plan.name, result.subscription_item.subscribable.name
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        business_id: @business.id, plan_name: @business.plan.name, purpose: @business_plan_subscription.purpose,
      }, business: @business])
    end

    test "updates a subscription item for the specified account's subscription, dealing with old 0-quantity subscription items" do
      old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

      create :billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org

      create :billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: new_listing_plan,
        quantity: 0,
        organization: @business_org

      assert_no_difference "Billing::SubscriptionItem.active.count" do
        assert_performed_jobs(1, only: SynchronizePlanSubscriptionJob) do
          result = Billing::UpdateSubscriptionItem.call(
            subscribable: new_listing_plan,
            quantity: 3,
            viewer: @business_owner_org_admin,
            plan_subscription: @business_plan_subscription,
            installation_account: @business_org
          )

          assert_equal 3, result.subscription_item.quantity
          assert_equal @business_org, result.subscription_item.organization
          assert_equal new_listing_plan.listing.name, result.subscription_item.subscribable.listing.name
          assert_equal new_listing_plan.name, result.subscription_item.subscribable.name
        end
      end

      assert_performed_with(job: SynchronizePlanSubscriptionJob, args: [{
        business_id: @business.id, plan_name: @business.plan.name, purpose: @business_plan_subscription.purpose,
      }, business: @business])
    end

    test "does not update subscription item for org admin that is not an EA owner" do
      non_business_owner = create(:user)
      old_listing_plan = create(:marketplace_listing_plan, :verified_listing)
      new_listing_plan = create(:marketplace_listing_plan, :published, listing: old_listing_plan.listing)

      subscription_item = create :billing_subscription_item,
        plan_subscription: @business_plan_subscription,
        subscribable: old_listing_plan,
        quantity: 1,
        organization: @business_org

      assert_performed_jobs(0, only: SynchronizePlanSubscriptionJob) do
        error = assert_raises Billing::UpdateSubscriptionItem::ForbiddenError do
          Billing::UpdateSubscriptionItem.call(
            subscribable: new_listing_plan,
            quantity: 3,
            viewer: non_business_owner,
            plan_subscription: @business_plan_subscription,
            installation_account: @business_org,
          )
        end

        assert_equal "#{non_business_owner} does not have permission to manage this account (#{@business})", error.message
      end

      subscription_item.reload
      assert_equal old_listing_plan, subscription_item.subscribable
      assert_equal @business_org, subscription_item.organization
    end
  end
end
