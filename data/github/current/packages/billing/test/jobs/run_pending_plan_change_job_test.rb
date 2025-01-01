# typed: true
# frozen_string_literal: true

require "test_helper"

class RunPendingPlanChangeJobTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  teardown do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  test "updates user's plan with scheduled changes" do
    org = create :organization, plan: "free", seats: 10
    change = org.pending_plan_changes.create \
      active_on: GitHub::Billing.today,
      plan: "silver",
      seats: 5

    RunPendingPlanChangeJob.perform_now(change)

    assert_equal GitHub::Plan.find("silver"), org.reload.plan
    assert_equal 5, org.reload.seats
  end

  test "doesn't run completed changes" do
    org = create :organization, plan: "free", seats: 10
    change = org.pending_plan_changes.create \
      active_on: GitHub::Billing.today,
      is_complete: true,
      plan: "silver",
      seats: 5

    RunPendingPlanChangeJob.perform_now(change)

    assert_equal GitHub::Plan.find("free"), org.reload.plan
    assert_equal 10, org.reload.seats
  end

  test "doesn't error out when the associated user is destroyed" do
    change = create :billing_pending_plan_change
    user = change.user

    user.destroy

    perform_enqueued_jobs(only: [RunPendingPlanChangeJob]) do
      RunPendingPlanChangeJob.perform_later(change)
    end
  end

  test "emits a Hydro event when a user plan is changed to free" do
    product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "pro",
      billing_cycle: "month",
    )
    user = create(:user, plan: "pro", plan_duration: "month")
    change = create(:billing_pending_plan_change, plan: "free", seats: nil, user: user, actor: user)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: 0,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    # We don't publish a BillingProduct create message because there's no product
    # for the free plan
    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a org plan is downgraded to a non-free plan" do
    business_product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "business",
      billing_cycle: "month",
    )
    business_plus_product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "business_plus",
      billing_cycle: "month",
    )
    actor = create(:user)
    org = create(:organization, plan: "business_plus", plan_duration: "month")
    change = create(:billing_pending_plan_change, plan: "business", seats: nil, user: org, actor: actor)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_actor = Hydro::EntitySerializer.user(actor)
    serialized_org = Hydro::EntitySerializer.user(org)

    expected_deletion_hydro_message = {
      actor: serialized_actor,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: 0,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: business_plus_product_uuid.id,
      },
      target_entity_owner: serialized_org,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_deletion_hydro_message, schema: "github.v1.UserBehavior")

    expected_creation_hydro_message = {
      actor: serialized_actor,
      resource: "BillingProduct",
      resource_action: "create",
      resource_quantity_delta: 0,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: business_product_uuid.id,
      },
      target_entity_owner: serialized_org,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_creation_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 2, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when an org decreases the number of seats on its plan" do
    product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "business",
      billing_cycle: "month",
    )
    actor = create(:user)
    org = create(:organization, plan: "business", plan_duration: "month", seats: 100)
    change = create(:billing_pending_plan_change, plan: nil, seats: 75, user: org, actor: actor)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_actor = Hydro::EntitySerializer.user(actor)
    serialized_org = Hydro::EntitySerializer.user(org)

    expected_hydro_message = {
      actor: serialized_actor,
      resource: "BillingProduct",
      resource_action: "change_quantity",
      resource_quantity_delta: -25,
      resource_quantity_total: 75,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_org,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a org plan is downgraded to a non-free plan and changes seats" do
    business_product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "business",
      billing_cycle: "month",
    )
    business_plus_product_uuid = create(
      :billing_product_uuid,
      product_type: "github.plan",
      product_key: "business_plus",
      billing_cycle: "month",
    )
    actor = create(:user)
    org = create(:organization, plan: "business_plus", seats: 100, plan_duration: "month")
    change = create(:billing_pending_plan_change, plan: "business", seats: 75, user: org, actor: actor)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_actor = Hydro::EntitySerializer.user(actor)
    serialized_org = Hydro::EntitySerializer.user(org)

    expected_deletion_hydro_message = {
      actor: serialized_actor,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: -100,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: business_plus_product_uuid.id,
      },
      target_entity_owner: serialized_org,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_deletion_hydro_message, schema: "github.v1.UserBehavior")

    expected_creation_hydro_message = {
      actor: serialized_actor,
      resource: "BillingProduct",
      resource_action: "create",
      resource_quantity_delta: 75,
      resource_quantity_total: 75,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: business_product_uuid.id,
      },
      target_entity_owner: serialized_org,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_creation_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 3, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a user decreases their LFS storage" do
    product_uuid = create(
      :billing_product_uuid,
      product_type: "github.lfs",
      product_key: "v0",
      billing_cycle: "month",
    )
    user = create(:user)
    Asset::Status.create!(owner: user, asset_packs: 5)
    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: 3, user: user, actor: user)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "change_quantity",
      resource_quantity_delta: -2,
      resource_quantity_total: 3,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a user removes all of their LFS storage" do
    product_uuid = create(
      :billing_product_uuid,
      product_type: "github.lfs",
      product_key: "v0",
      billing_cycle: "month",
    )
    user = create(:user)
    Asset::Status.create!(owner: user, asset_packs: 5)
    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: 0, user: user, actor: user)

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: -5,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a user downgrades a Marketplace product to a different listing plan" do
    listing = create(:marketplace_listing, :verified)

    old_listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
    old_product_uuid = create(
      :billing_product_uuid,
      product_type: "marketplace.listing_plan",
      product_key: old_listing_plan.id.to_s,
      billing_cycle: "month",
    )

    new_listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
    new_product_uuid = create(
      :billing_product_uuid,
      product_type: "marketplace.listing_plan",
      product_key: new_listing_plan.id.to_s,
      billing_cycle: "month",
    )

    user = create(:user)
    create(
      :billing_subscription_item,
      plan_subscription: create(:billing_plan_subscription, user: user),
      subscribable: old_listing_plan,
      quantity: 1,
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: new_listing_plan,
      quantity: 1,
    )

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_deletion_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: -1,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: old_product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_deletion_hydro_message, schema: "github.v1.UserBehavior")

    expected_creation_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "create",
      resource_quantity_delta: 1,
      resource_quantity_total: 1,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: new_product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_creation_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 2, schema: "github.v1.UserBehavior")
  end

  test "updates Sponsorship when user downgrades to a lower tier" do
    sponsorship = create(:sponsorship)
    sponsorable = sponsorship.sponsorable
    sponsor = sponsorship.sponsor
    sponsors_listing = sponsorable.sponsors_listing
    original_tier = sponsorship.subscription_item.subscribable

    downgraded_tier = create(:sponsors_tier, :published, listing: sponsors_listing,
      monthly_price_in_cents: original_tier.monthly_price_in_cents - 100,
      yearly_price_in_cents: original_tier.yearly_price_in_cents - 1200
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: sponsor, actor: sponsor)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: downgraded_tier,
      quantity: 1,
    )

    RunPendingPlanChangeJob.perform_now(change)
    sponsorship.reload

    assert_equal downgraded_tier, sponsorship.subscription_item.subscribable
  end

  test "emits a Hydro event when a user removes a Marketplace product" do
    listing_plan = create(:marketplace_listing_plan, :published, :verified_listing)
    product_uuid = create(
      :billing_product_uuid,
      product_type: "marketplace.listing_plan",
      product_key: listing_plan.id.to_s,
      billing_cycle: "month",
    )

    user = create(:user)
    create(
      :billing_subscription_item,
      plan_subscription: create(:billing_plan_subscription, user: user),
      subscribable: listing_plan,
      quantity: 1,
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: listing_plan,
      quantity: 0,
    )

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "delete",
      resource_quantity_delta: -1,
      resource_quantity_total: 0,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "does not emit a Hydro event when a user removes a Sponsorship product" do
    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    create(
      :billing_product_uuid,
      product_type: SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE,
      product_key: sponsors_tier.id.to_s,
      billing_cycle: "month",
    )

    user = create(:user)
    create(
      :sponsors_subscription_item,
      account: user,
      subscribable: sponsors_tier,
      quantity: 1,
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: sponsors_tier,
      quantity: 0,
    )

    RunPendingPlanChangeJob.perform_now(change)

    assert_hydro_messages(count: 0, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a user decreases the quantity of a Marketplace product" do
    listing_plan = create(:marketplace_listing_plan, :published, :verified_listing)
    product_uuid = create(
      :billing_product_uuid,
      product_type: "marketplace.listing_plan",
      product_key: listing_plan.id.to_s,
      billing_cycle: "month",
    )

    user = create(:user)
    create(
      :billing_subscription_item,
      plan_subscription: create(:billing_plan_subscription, user: user),
      subscribable: listing_plan,
      quantity: 5,
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: listing_plan,
      quantity: 2,
    )

    RunPendingPlanChangeJob.perform_now(change)

    serialized_user = Hydro::EntitySerializer.user(user)

    expected_hydro_message = {
      actor: serialized_user,
      resource: "BillingProduct",
      resource_action: "change_quantity",
      resource_quantity_delta: -3,
      resource_quantity_total: 2,
      target_entity: {
        entity_type: :BILLING_PRODUCT,
        entity_id: product_uuid.id,
      },
      target_entity_owner: serialized_user,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
    }
    assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

    assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
  end

  test "does not emit a Hydro event when a user decreases the quantity of a Sponsorship product" do
    sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
    create(
      :billing_product_uuid,
      product_type: SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE,
      product_key: sponsors_tier.id.to_s,
      billing_cycle: "month",
    )

    user = create(:user)
    create(
      :sponsors_subscription_item,
      account: user,
      subscribable: sponsors_tier,
      quantity: 5,
    )

    change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
    create(
      :billing_pending_subscription_item_change,
      pending_plan_change: change,
      subscribable: sponsors_tier,
      quantity: 2,
    )

    RunPendingPlanChangeJob.perform_now(change)

    assert_hydro_messages(count: 0, schema: "github.v1.UserBehavior")
  end

  test "emits a Hydro event when a Marketplace product continues to be used after a free-trial" do
    Timecop.freeze do
      listing_plan = create(:marketplace_listing_plan, :published, :verified_listing)
      product_uuid = create(
        :billing_product_uuid,
        product_type: "marketplace.listing_plan",
        product_key: listing_plan.id.to_s,
        billing_cycle: "month",
      )

      user = create(:user)
      create(
        :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: listing_plan,
        quantity: 2,
        free_trial_ends_on: Date.today,
      )

      change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
      create(
        :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: listing_plan,
        quantity: 2,
        free_trial: true,
      )

      RunPendingPlanChangeJob.perform_now(change)

      serialized_user = Hydro::EntitySerializer.user(user)

      expected_hydro_message = {
        actor: serialized_user,
        resource: "BillingProduct",
        resource_action: "free_trial_conversion",
        resource_quantity_delta: 0,
        resource_quantity_total: 2,
        target_entity: {
          entity_type: :BILLING_PRODUCT,
          entity_id: product_uuid.id,
        },
        target_entity_owner: serialized_user,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.UserBehavior")

      assert_hydro_messages(count: 1, schema: "github.v1.UserBehavior")
    end
  end

  test "emits a Hydro event when a Marketplace product changes to another listing plan after a free-trial" do
    Timecop.freeze do
      listing = create(:marketplace_listing, :verified)

      old_listing_plan = create(:marketplace_listing_plan, :published, listing: listing)
      new_listing_plan = create(:marketplace_listing_plan, :published, listing: listing)

      old_product_uuid = create(
        :billing_product_uuid,
        product_type: "marketplace.listing_plan",
        product_key: old_listing_plan.id.to_s,
        billing_cycle: "month",
      )
      new_product_uuid = create(
        :billing_product_uuid,
        product_type: "marketplace.listing_plan",
        product_key: new_listing_plan.id.to_s,
        billing_cycle: "month",
      )

      user = create(:user)
      create(
        :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: old_listing_plan,
        quantity: 2,
        free_trial_ends_on: Date.today,
      )

      change = create(:billing_pending_plan_change, plan: nil, seats: nil, data_packs: nil, user: user, actor: user)
      create(
        :billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: new_listing_plan,
        quantity: 2,
        free_trial: true,
      )

      RunPendingPlanChangeJob.perform_now(change)

      serialized_user = Hydro::EntitySerializer.user(user)

      expected_deletion_hydro_message = {
        actor: serialized_user,
        resource: "BillingProduct",
        resource_action: "delete",
        resource_quantity_delta: -2,
        resource_quantity_total: 0,
        target_entity: {
          entity_type: :BILLING_PRODUCT,
          entity_id: old_product_uuid.id,
        },
        target_entity_owner: serialized_user,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }
      assert_hydro_published(expected_deletion_hydro_message, schema: "github.v1.UserBehavior")

      expected_creation_hydro_message = {
        actor: serialized_user,
        resource: "BillingProduct",
        resource_action: "create",
        resource_quantity_delta: 2,
        resource_quantity_total: 2,
        target_entity: {
          entity_type: :BILLING_PRODUCT,
          entity_id: new_product_uuid.id,
        },
        target_entity_owner: serialized_user,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }
      assert_hydro_published(expected_creation_hydro_message, schema: "github.v1.UserBehavior")

      expected_free_trial_hydro_message = {
        actor: serialized_user,
        resource: "BillingProduct",
        resource_action: "free_trial_conversion",
        resource_quantity_delta: 0,
        resource_quantity_total: 2,
        target_entity: {
          entity_type: :BILLING_PRODUCT,
          entity_id: new_product_uuid.id,
        },
        target_entity_owner: serialized_user,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }
      assert_hydro_published(expected_free_trial_hydro_message, schema: "github.v1.UserBehavior")

      assert_hydro_messages(count: 3, schema: "github.v1.UserBehavior")
    end
  end

  test "enqueues a single synchronization for each plan subscription related to a pending change" do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

    admin = create(:user)
    org = create(:credit_card_org,
      plan_subscription: create(:billing_plan_subscription, :zuora),
      admin: admin,
      plan: GitHub::Plan.business,
    )
    marketplace_plan = create(:marketplace_listing_plan, :published)
    copilot_product_uuid = create(:billing_product_uuid, :copilot)
    sponsors_tier_1, sponsors_tier_2 = create_pair(:sponsors_tier, :published)
    sponsors_tiers = [sponsors_tier_1, sponsors_tier_2]
    general_subscribables = [marketplace_plan, copilot_product_uuid]
    subscribables = sponsors_tiers + general_subscribables
    change = create(:billing_pending_plan_change, plan: nil, user: org, actor: admin)

    general_subscribables.each do |subscribable|
      create(:billing_subscription_item,
        account: org,
        subscribable: subscribable,
        quantity: 1,
      )
    end
    sponsors_tiers.each do |tier|
      create(:sponsors_subscription_item,
        account: org,
        subscribable: tier,
        quantity: 1,
      )
    end
    subscribables.each do |subscribable|
      create(:billing_pending_subscription_item_change,
        pending_plan_change: change,
        subscribable: subscribable,
        quantity: 0,
      )
    end

    assert_enqueued_jobs 2, only: SynchronizePlanSubscriptionJob do
      RunPendingPlanChangeJob.perform_now(change)
    end
  end

  test "enqueues synchronization for the general billable entity's plan subscription even when subscription item charge is not present" do
    self.perform_enqueued_jobs = false # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

    admin = create(:user)
    org = create(:credit_card_org,
      plan_subscription: create(:billing_plan_subscription, :zuora),
      admin: admin,
      plan: GitHub::Plan.business,
    )
    marketplace_plan = create(:marketplace_listing_plan, :published)
    copilot_product_uuid = create(:billing_product_uuid, :copilot)
    sponsors_tier_1, sponsors_tier_2 = create_pair(:sponsors_tier, :published)
    sponsors_tiers = [sponsors_tier_1, sponsors_tier_2]
    general_subscribables = [copilot_product_uuid]
    subscribables = sponsors_tiers + general_subscribables
    change = create(:billing_pending_plan_change, plan: nil, user: org, actor: admin)

    general_subscribables.each do |subscribable|
      create(:billing_subscription_item,
        account: org,
        subscribable: subscribable,
        quantity: 1,
      )
    end
    sponsors_tiers.each do |tier|
      create(:sponsors_subscription_item,
        account: org,
        subscribable: tier,
        quantity: 1,
      )
    end
    subscribables.each do |subscribable|
      unless subscribable.is_a?(Billing::ProductUUID)
        create(:billing_pending_subscription_item_change,
          pending_plan_change: change,
          subscribable: subscribable,
          quantity: 0,
        )
      end
    end

    assert_enqueued_jobs 2, only: SynchronizePlanSubscriptionJob do
      RunPendingPlanChangeJob.perform_now(change)
    end
  end

  test "it reenqueues if the plan change is not yet active" do
    org = create :organization, plan: "free", seats: 10
    change = org.pending_plan_changes.create \
      active_on: 5.days.from_now,
      plan: "silver",
      seats: 5

    sched_time = change.active_on.to_time
    RunPendingPlanChangeJob.any_instance.stubs(:rand).returns(7)
    sched_time = change.active_on.to_time + 7.seconds

    assert_enqueued_with(job: RunPendingPlanChangeJob, at: sched_time) do
      RunPendingPlanChangeJob.perform_now(change)
    end

    assert_equal GitHub::Plan.find("free"), org.reload.plan
    assert_equal 10, org.reload.seats
  end

  test "it retries on Zuorest::TooManyRequestsError" do
    org = create :organization, plan: "free", seats: 10
    change = org.pending_plan_changes.create \
      active_on: 5.days.ago,
      plan: "silver",
      seats: 5

    freeze_time do
      change.stub(:run, -> { raise Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }) }) do
        assert_enqueued_with(job: RunPendingPlanChangeJob, at: Time.now + 600) do
          RunPendingPlanChangeJob.perform_now(change)
        end
      end
    end
  end

  test "it retries on Zuorest::TooManyRequestsError 7 times" do
    org = create :organization, plan: "free", seats: 10
    change = org.pending_plan_changes.create \
      active_on: 5.days.ago,
      plan: "silver",
      seats: 5

    attempts_per_exception = { "[Zuorest::TooManyRequestsError]" => 6 }
    RunPendingPlanChangeJob.any_instance.stubs(:exception_executions).returns(attempts_per_exception)

    freeze_time do
      change.stub(:run, -> { raise Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" }) }) do
        assert_no_enqueued_jobs do
          RunPendingPlanChangeJob.perform_now(change)
        end
      end
    end
  end
end if GitHub.billing_enabled?
