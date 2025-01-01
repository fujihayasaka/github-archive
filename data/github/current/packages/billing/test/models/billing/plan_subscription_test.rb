# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscriptionTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper
    include GitHub::SponsorsZuoraTestHelper
    include GitHub::Billing::CurrencyTestHelper
    include GitHub::LoggerHelper
    include AuditLog::IntegrationTestHelpers
    include DogstatsTestHelpers

    setup do
      GitHub::Experiment.raise_on_mismatches = false
      setup_currency_exchange
      synchronize_github_products_to_zuora
      enable_feature_flag(:new_zuora_rate_plan_charges)
    end

    context "#plan_change" do
      test "returns a plan change to add a new subscription item with a subscribable" do
        listing = create(:marketplace_listing, :verified, :with_plans)
        subscribable = listing.listing_plans.first
        plan_sub = create(:billing_plan_subscription)
        user = plan_sub.user

        plan_change = plan_sub.plan_change(subscribable: subscribable, billable_entity: user)

        assert_instance_of Billing::PlanChange, plan_change

        refute_nil plan_change.old_subscription
        refute_nil plan_change.new_subscription
        assert_equal plan_change.old_subscription.plan, plan_change.new_subscription.plan
        assert_equal plan_change.old_subscription.seats, plan_change.new_subscription.seats
        assert_equal plan_change.old_subscription.duration_in_months, plan_change.new_subscription.duration_in_months

        assert_empty plan_change.old_subscription.subscription_items
        assert_equal 1, plan_change.new_subscription.subscription_items.size

        new_sub_item = plan_change.new_subscription.subscription_items.first
        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_equal 0, new_sub_item.quantity
        assert_equal subscribable, new_sub_item.subscribable
        assert_predicate new_sub_item, :new_record?
      end

      test "returns a plan change to change subscribables for the same listing" do
        listing = create(:marketplace_listing, :verified)
        old_subscribable, new_subscribable = create_pair(:marketplace_listing_plan, :paid, listing: listing)
        plan_sub = create(:billing_plan_subscription)
        old_sub_item = create(:billing_subscription_item, subscribable: old_subscribable, plan_subscription: plan_sub)
        user = plan_sub.user

        plan_change = plan_sub.plan_change(subscribable: new_subscribable, billable_entity: user)

        assert_instance_of Billing::PlanChange, plan_change

        refute_nil plan_change.old_subscription
        refute_nil plan_change.new_subscription
        assert_equal plan_change.old_subscription.plan, plan_change.new_subscription.plan
        assert_equal plan_change.old_subscription.seats, plan_change.new_subscription.seats
        assert_equal plan_change.old_subscription.duration_in_months, plan_change.new_subscription.duration_in_months

        assert_equal 1, plan_change.old_subscription.subscription_items.size
        assert_equal 1, plan_change.new_subscription.subscription_items.size

        assert_equal old_sub_item, plan_change.old_subscription.subscription_items.first

        new_sub_item = plan_change.new_subscription.subscription_items.first
        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_equal 0, new_sub_item.quantity
        assert_equal new_subscribable, new_sub_item.subscribable
        assert_predicate new_sub_item, :new_record?
      end

      test "returns a plan change to switch plans" do
        user = create(:user, plan: "free")
        plan_sub = create(:billing_plan_subscription, user: user)

        plan_change = plan_sub.plan_change(plan: "pro", billable_entity: user)

        assert_instance_of Billing::PlanChange, plan_change

        refute_nil plan_change.old_subscription
        refute_nil plan_change.new_subscription
        assert_equal "free", plan_change.old_subscription.plan.name
        assert_equal "pro", plan_change.new_subscription.plan.name
        assert_equal plan_change.old_subscription.seats, plan_change.new_subscription.seats
        assert_equal plan_change.old_subscription.duration_in_months, plan_change.new_subscription.duration_in_months
        assert_empty plan_change.old_subscription.subscription_items
        assert_empty plan_change.new_subscription.subscription_items
      end
    end

    context "#with_purpose scope"  do
      test "returns only sponsors-purpose plans when purpose is sponsors" do
        sponsors_purpose_plan = create(:billing_plan_subscription, :sponsors_invoiced)
        general_purpose_plan = create(:billing_plan_subscription)

        result = Billing::PlanSubscription.with_purpose(:sponsors)

        assert_includes result, sponsors_purpose_plan
        refute_includes result, general_purpose_plan
      end

      test "returns only general-purpose plans when purpose is general" do
        sponsors_purpose_plan = create(:billing_plan_subscription, :sponsors_invoiced)
        general_purpose_plan = create(:billing_plan_subscription)

        result = Billing::PlanSubscription.with_purpose(:general)

        assert_includes result, general_purpose_plan
        refute_includes result, sponsors_purpose_plan
      end
    end

    context "#active_charges?" do
      test "retuns true for paid plans for a general-purpose subscription" do
        subscription = create(:billing_plan_subscription, user: create(:user))
        refute_predicate subscription.plan, :paid?
        refute_predicate subscription, :active_charges?

        subscription = create(:billing_plan_subscription, user: create(:paid_user))
        assert_predicate subscription.plan, :paid?
        assert_predicate subscription, :active_charges?
      end

      # https://github.com/github/sponsors/issues/4928
      test "returns false for a Sponsors-specific subscription that has no active subscription items even when billable entity is on a paid plan with data packs" do
        user = create(:paid_user, :with_lfs_data_packs)
        assert_predicate user.plan, :paid?
        subscription = create(:billing_plan_subscription, :sponsors_invoiced, user: user)
        refute_predicate subscription, :active_charges?
      end

      test "returns true for users with data packs" do
        subscription = create(:billing_plan_subscription, user: create(:user))
        refute_predicate subscription, :active_charges?

        subscription = create(:billing_plan_subscription, user: create(:user, :with_lfs_data_packs))
        assert_predicate subscription, :active_charges?
      end

      test "returns true for users with metered overages enabled" do
        subscription = create(:billing_plan_subscription)
        refute_predicate subscription, :active_charges?

        create(:billing_budget, owner: subscription.user)
        assert_predicate subscription, :active_charges?
      end

      test "returns true for users with active subscription items" do
        subscription = create(:billing_plan_subscription)
        refute_predicate subscription, :active_charges?

        create(:billing_subscription_item, :with_product_uuid, plan_subscription: subscription)
        assert_predicate subscription.reload, :active_charges?
      end

      test "returns true for orgs with an active CFB subscription" do
        org = create :organization, plan: "free"
        ::Copilot::Organization.new(org).enable_copilot!
        plan_subscription = create(:billing_plan_subscription, user: org)

        assert_predicate plan_subscription, :active_charges?
      end
    end

    context "#async_subscription_item_for" do
      test "resolves to nil when given nil" do
        plan_sub = create(:billing_plan_subscription)
        assert_nil plan_sub.async_subscription_item_for(nil).sync
      end

      test "resolves to nil when the plan subscription has no subscription items" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)
        assert_nil plan_sub.async_subscription_item_for(subscribable).sync
      end

      test "resolves to nil when the plan subscription does not have a subscription item for the given subscribable" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)
        create(:billing_subscription_item, plan_subscription: plan_sub)
        assert_nil plan_sub.async_subscription_item_for(subscribable).sync
      end

      test "resolves to subscription item on the plan subscription that matches the given subscribable" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)

        create(:billing_subscription_item, plan_subscription: plan_sub) # other subscription item
        sub_item = create(:billing_subscription_item, plan_subscription: plan_sub, subscribable: subscribable)

        assert_equal sub_item, plan_sub.async_subscription_item_for(subscribable).sync
      end
    end

    context "#async_new_subscription_item_for" do
      test "resolves to an unsaved subscription item for the plan subscription using the given subscribable" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)

        sub_item = plan_sub.async_new_subscription_item_for(subscribable).sync

        assert_instance_of Billing::SubscriptionItem, sub_item
        assert_predicate sub_item, :new_record?
        assert_equal plan_sub, sub_item.plan_subscription
        assert_equal 0, sub_item.quantity
        assert_equal subscribable, sub_item.subscribable
        assert_nil sub_item.free_trial_ends_on
      end

      test "respects given subscribable quantity" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)

        sub_item = plan_sub.async_new_subscription_item_for(subscribable, subscribable_quantity: 1).sync

        assert_instance_of Billing::SubscriptionItem, sub_item
        assert_predicate sub_item, :new_record?
        assert_equal plan_sub, sub_item.plan_subscription
        assert_equal 1, sub_item.quantity
        assert_equal subscribable, sub_item.subscribable
        assert_nil sub_item.free_trial_ends_on
      end

      test "preserves free trial date on existing subscription item for the subscribable" do
        subscribable = create(:marketplace_listing_plan, :verified_listing)
        plan_sub = create(:billing_plan_subscription)
        existing_sub_item = create(:billing_subscription_item, plan_subscription: plan_sub,
          subscribable: subscribable, free_trial_ends_on: 3.months.from_now)

        new_sub_item = plan_sub.async_new_subscription_item_for(subscribable).sync

        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_predicate new_sub_item, :new_record?
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_equal 0, new_sub_item.quantity
        assert_equal subscribable, new_sub_item.subscribable
        assert_equal existing_sub_item.free_trial_ends_on, new_sub_item.free_trial_ends_on
      end
    end

    context "business subscription" do
      test "subscription for business has no user" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        assert_nil plan_subscription.user
        assert_nil plan_subscription.user_id
        refute_nil plan_subscription.business
      end

      test "can create multiple Business subscriptions" do
        create :billing_plan_subscription, :business_owned

        business = create :business
        business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)
        business.customer.create_plan_subscription!
      end
    end

    context "#async_subscription_items_for_new_subscription" do
      test "resolves to nil when given no subscribable" do
        plan_sub = create(:billing_plan_subscription)
        create(:billing_subscription_item, plan_subscription: plan_sub)

        assert_nil plan_sub.async_subscription_items_for_new_subscription(subscribable: nil).sync
      end

      test "resolves to a list with a new subscription item for the given new subscribable" do
        plan_sub = create(:billing_plan_subscription)
        subscribable = create(:marketplace_listing_plan, :verified_listing)

        result = plan_sub.async_subscription_items_for_new_subscription(subscribable: subscribable).sync

        assert_equal 1, result.size
        new_sub_item = result.first
        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_equal 0, new_sub_item.quantity
        assert_equal subscribable, new_sub_item.subscribable
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_nil new_sub_item.free_trial_ends_on
        assert_predicate new_sub_item, :new_record?
      end

      test "resolves to a list including existing subscription items and a new subscription item for the given new subscribable" do
        plan_sub = create(:billing_plan_subscription)
        existing_sub_item = create(:billing_subscription_item, plan_subscription: plan_sub)
        new_subscribable = create(:marketplace_listing_plan, :verified_listing)

        result = plan_sub.async_subscription_items_for_new_subscription(subscribable: new_subscribable).sync

        assert_equal 2, result.size
        assert_equal existing_sub_item, result.detect { |item| item.subscribable == existing_sub_item.subscribable }

        new_sub_item = result.detect { |item| item.subscribable == new_subscribable }
        refute_nil new_sub_item
        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_equal 0, new_sub_item.quantity
        assert_equal new_subscribable, new_sub_item.subscribable
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_nil new_sub_item.free_trial_ends_on
        assert_predicate new_sub_item, :new_record?
      end

      test "resolves to a list with just a new subscription item when existing subscription item's subscribable is for the same listing as given subscribable" do
        plan_sub = create(:billing_plan_subscription)
        existing_subscribable = create(:marketplace_listing_plan, :verified_listing)
        create(:billing_subscription_item, plan_subscription: plan_sub, subscribable: existing_subscribable)
        new_subscribable = create(:marketplace_listing_plan, listing: existing_subscribable.listing)

        result = plan_sub.async_subscription_items_for_new_subscription(subscribable: new_subscribable).sync

        assert_equal 1, result.size
        new_sub_item = result.first
        assert_instance_of Billing::SubscriptionItem, new_sub_item
        assert_equal 0, new_sub_item.quantity
        assert_equal new_subscribable, new_sub_item.subscribable
        assert_equal plan_sub, new_sub_item.plan_subscription
        assert_nil new_sub_item.free_trial_ends_on
        assert_predicate new_sub_item, :new_record?
      end
    end

    context "#billable" do
      test "returns user when subscription is owned by a user" do
        plan_subscription = create(:billing_plan_subscription)
        assert plan_subscription.billable_user?
        assert_equal plan_subscription.user, plan_subscription.billable_entity
      end

      test "returns business when subscription is owned by a business" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        assert plan_subscription.billable_business?
        assert_equal plan_subscription.business, plan_subscription.billable_entity
      end
    end

    context "#subscribed_to_github_plan?" do
      test "returns false if the user doesn't exist" do
        plan_subscription = create(:billing_plan_subscription)
        plan_subscription.user.destroy
        plan_subscription.user = nil
        refute plan_subscription.subscribed_to_github_plan?(plan: GitHub::Plan.free)
      end

      test "returns true when the plan matches the user's plan" do
        plan_subscription = create(:billing_plan_subscription)
        assert plan_subscription.subscribed_to_github_plan?(plan: plan_subscription.plan)
        assert plan_subscription.subscribed_to_github_plan?(plan: plan_subscription.plan.to_s)
      end

      test "returns false when the plans don't match" do
        plan_subscription = create(:billing_plan_subscription)
        plan_subscription.user.plan = GitHub::Plan.pro
        refute plan_subscription.subscribed_to_github_plan?(plan: GitHub::Plan.business)
        refute plan_subscription.subscribed_to_github_plan?(plan: GitHub::Plan.business.to_s)
      end

      test "returns true when the plan matches the business's plan" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        assert plan_subscription.subscribed_to_github_plan?(plan: plan_subscription.plan)
        assert plan_subscription.subscribed_to_github_plan?(plan: plan_subscription.plan.to_s)
      end

      test "returns true when the plan doesn't match the business's plan" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        refute plan_subscription.subscribed_to_github_plan?(plan: GitHub::Plan.pro)
        refute plan_subscription.subscribed_to_github_plan?(plan: GitHub::Plan.pro.to_s)
      end
    end

    context "#update_from_zuora_subscription" do
      test "raises an error if the subscription is not found" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        GitHub.zuorest_client.expects(:get_subscription).returns({ "success" => false })

        assert_raises Billing::Zuora::Subscription::NotFoundError do
          plan_subscription.update_from_zuora_subscription
        end
      end

      test "uses the subscription data from the argument first" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            "accountId" => "new-id",
            "subscribeToRatePlans" => [
              {
                "productRatePlanId" => "product-rate-plan-id",
                "chargeOverrides" => [{
                  "number": "C-123",
                  "chargedThroughDate": Date.parse("2023-05-04"),
                  "productRatePlanChargeId": "matching-id",
                }.with_indifferent_access],
              },
            ],
          },
        )
        zuora_subscription = Billing::Zuora::Subscription.find(plan_subscription.zuora_subscription_number)

        plan_subscription.expects(:reset_memoized_attributes).never
        plan_subscription.expects(:zuora_subscription).never

        plan_subscription.update_from_zuora_subscription(zuora_subscription_object: zuora_subscription)
        assert_equal "C-123", plan_subscription.zuora_rate_plan_charges.dig("matching-id", :number)
        assert_equal Date.parse("2023-05-04"), plan_subscription.zuora_rate_plan_charges.dig("matching-id", :charged_through_date)

        if GitHub.flipper[:new_zuora_rate_plan_charges].enabled?
          assert_equal 1, plan_subscription.subscription_rate_plan_charges.count
          zuora_rate_plan_charge = plan_subscription.subscription_rate_plan_charges.first

          assert_equal "matching-id", zuora_rate_plan_charge.product_rate_plan_charge_id
          assert_equal "C-123", zuora_rate_plan_charge.number
          assert_equal Date.parse("2023-05-04"), zuora_rate_plan_charge.charged_through_date
        end
      end

      test "updates the subscription ID and rate plan charges" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            "accountId" => "new-id",
            "subscribeToRatePlans" => [
              {
                "productRatePlanId" => "product-rate-plan-id",
                "chargeOverrides" => [{
                  "number": "C-123",
                  "chargedThroughDate": Date.parse("2023-05-04"),
                  "productRatePlanChargeId": "matching-id",
                }.with_indifferent_access],
              },
            ],
          },
        )

        plan_subscription.update_from_zuora_subscription

        assert_equal "C-123", plan_subscription.zuora_rate_plan_charges.dig("matching-id", :number)
        assert_equal Date.parse("2023-05-04"), plan_subscription.zuora_rate_plan_charges.dig("matching-id", :charged_through_date)

        if GitHub.flipper[:new_zuora_rate_plan_charges].enabled?
          assert_equal 1, plan_subscription.subscription_rate_plan_charges.count
          zuora_rate_plan_charge = plan_subscription.subscription_rate_plan_charges.first

          assert_equal "matching-id", zuora_rate_plan_charge.product_rate_plan_charge_id
          assert_equal "C-123", zuora_rate_plan_charge.number
          assert_equal Date.parse("2023-05-04"), zuora_rate_plan_charge.charged_through_date
        end
      end
    end

    context "#zuora_rate_plan_charge_number" do
      test "returns nil when the product rate plan charge ID doesn't match" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        assert_nil plan_subscription.zuora_rate_plan_charge_number(
          product_rate_plan_charge_id: "mismatch",
        )
      end

      test "returns the rate plan charge number if there's a product rate plan charge ID match" do
        rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
        product_rate_plan_charge_id = rate_plan_charge[:productRatePlanChargeId]
        rate_plan_charges = {
          product_rate_plan_charge_id => {
            number: rate_plan_charge[:number],
            charged_through_date: Date.parse(rate_plan_charge[:chargedThroughDate])
          }
        }
        plan_subscription = create(:billing_plan_subscription, zuora_rate_plan_charges: rate_plan_charges)
        create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_subscription, payload: rate_plan_charge)

        assert_equal rate_plan_charge[:number], plan_subscription.zuora_rate_plan_charge_number(
          product_rate_plan_charge_id: rate_plan_charge[:productRatePlanChargeId],
        )
      end
    end

    context "#suspend" do
      test "updates the subscription on success" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            accountId: "suspended-zuora-subscription",
            subscribeToRatePlans: [
              {
                productRatePlanId: "product-rate-plan-id",
                chargeOverrides:  [{
                  number: "C-123",
                  productRatePlanChargeId: "matching-id",
                }],
              },
            ],
          }.with_indifferent_access,
        )

        events = assert_performed_audit_entries(count: 1, only: "plan_subscription.suspend") do
          plan_subscription.suspend
        end

        assert events.first.has_key?(:plan_subscription_id)
        assert_equal plan_subscription.id, events.first[:plan_subscription_id]

        plan_subscription.zuora_subscription
        assert_equal "C-123", plan_subscription.zuora_rate_plan_charges.dig("matching-id", :number)
      end

      test "doesn't call zuora if subscription is already suspended" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            accountId: "resume-zuora-subscription",
            subscribeToRatePlans: [
              {
                productRatePlanId: "product-rate-plan-id",
                chargeOverrides:  [{
                  number: "C-123",
                  productRatePlanChargeId: "matching-id",
                }],
              },
            ],
          }.with_indifferent_access
        )
        PlanSubscription.any_instance.expects(:update).never
        Billing::Zuora::Subscription.any_instance.stubs(:suspended?).returns(true)

        assert_performed_audit_entries(count: 0, only: "plan_subscription.suspend") do
          plan_subscription.suspend
        end
      end
    end

    context "#resume" do
      test "updates the subscription on success" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            accountId: "resume-zuora-subscription",
            subscribeToRatePlans: [
              {
                productRatePlanId: "product-rate-plan-id",
                chargeOverrides:  [{
                  number: "C-123",
                  productRatePlanChargeId: "matching-id",
                }],
              },
            ],
          }.with_indifferent_access
        )
        Billing::Zuora::Subscription.any_instance.stubs(:suspended?).returns(true)


        events = assert_performed_audit_entries(count: 1, only: "plan_subscription.resume") do
          plan_subscription.resume
        end

        assert events.first.has_key?(:plan_subscription_id)
        assert_equal plan_subscription.id, events.first[:plan_subscription_id]

        assert_equal "C-123", plan_subscription.zuora_rate_plan_charges.dig("matching-id", :number)
      end

      test "doesn't call zuora if subscription is already resumed" do
        plan_subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_product_uuid, :github_plan, zuora_product_rate_plan_id: "product-rate-plan-id")
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            accountId: "resume-zuora-subscription",
            subscribeToRatePlans: [
              {
                productRatePlanId: "product-rate-plan-id",
                chargeOverrides:  [{
                  number: "C-123",
                  productRatePlanChargeId: "matching-id",
                }],
              },
            ],
          }.with_indifferent_access
        )
        PlanSubscription.any_instance.expects(:update).never
        Billing::Zuora::Subscription.any_instance.stubs(:suspended?).returns(false)

        assert_performed_audit_entries(count: 0, only: "plan_subscription.resume") do
          plan_subscription.resume
        end
      end
    end

    context ".active_subscription_items" do
      test "includes active subscription items" do
        subscription = create :billing_plan_subscription
        subscription_item = create(:billing_subscription_item, plan_subscription: subscription)

        assert_equal [subscription_item], subscription.active_subscription_items.reload
      end

      test "does not include cancelled subscription items" do
        subscription = create :billing_plan_subscription
        create(:billing_subscription_item, :cancelled, plan_subscription: subscription)

        assert_empty subscription.active_subscription_items
      end
    end

    context ".active_marketplace_listing_subscription_items" do
      test "returns active marketplace listing subscription items" do
        subscription = create :billing_plan_subscription

        listing_plan = create(:marketplace_listing_plan, :verified_listing)
        listing_plan2 = create(:marketplace_listing_plan, :verified_listing)

        subscription_item = create :billing_subscription_item,
          plan_subscription: subscription,
          subscribable: listing_plan,
          quantity: 1

        create(:billing_subscription_item, :cancelled,
          quantity: 0,
          plan_subscription: subscription,
          subscribable: listing_plan2)

        assert_equal [subscription_item], subscription.active_marketplace_listing_subscription_items
      end

      test "does not return subscription items that are not marketplace listings" do
        plan_subscription = create(:billing_plan_subscription)
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        create(:sponsorship, tier: tier, sponsor: plan_subscription.user)

        assert_equal [], plan_subscription.active_marketplace_listing_subscription_items
      end
    end

    context "#cancel_external_subscription" do
      test "enqueues CloseOutZuoraSubscriptionJob if there are no active non-metered charges on the plan subscription" do
        subscription = create(:billing_plan_subscription, :zuora)
        create(:billing_subscription_item, :with_product_uuid, :free, plan_subscription: subscription)

        refute subscription.active_non_metered_charges?
        assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
          subscription.cancel_external_subscription
        end
      end

      test "does not enqueue CloseOutZuoraSubscriptionJob if there are active non-metered charges on the plan subscription" do
        subscription = create(:billing_plan_subscription, :zuora, user: create(:paid_user))

        assert subscription.active_non_metered_charges?
        assert_enqueued_jobs(0, only: CloseOutZuoraSubscriptionJob) do
          subscription.cancel_external_subscription
        end
      end

      test "enqueues CloseOutZuoraSubscriptionJob if there are active non-metered charges on the plan subscription if force is true" do
        subscription = create(:billing_plan_subscription, :zuora, user: create(:paid_user))

        assert subscription.active_non_metered_charges?
        assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
          subscription.cancel_external_subscription(force: true)
        end
      end
    end

    context "#cancel_subscription_items!" do
      test "immediately cancels all paid subscription items and enqueues synchronization" do
        general_purpose_plan = create(:billing_plan_subscription)
        sponsors_purpose_plan = create(:billing_plan_subscription, :sponsors_invoiced)

        unpaid_sub_item = create(:billing_subscription_item, :free,
          plan_subscription: general_purpose_plan,
        )
        paid_sub_item1, paid_sub_item2 = create_pair(:billing_subscription_item, :paid,
          plan_subscription: general_purpose_plan,
        )

        other_plan_sub_item = create(:sponsors_subscription_item,
          plan_subscription: sponsors_purpose_plan,
        )

        [unpaid_sub_item, paid_sub_item1, paid_sub_item2, other_plan_sub_item].each do |sub_item|
          assert_predicate sub_item, :active?, "all sub items should be active before cancellation"
        end

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          results = general_purpose_plan.cancel_subscription_items!

          assert_same_elements [paid_sub_item1, paid_sub_item2], results.map(&:subscription_item)
          assert results.all? { |result| result.result.success }, "all results should be successful"
        end

        [unpaid_sub_item, paid_sub_item1, paid_sub_item2, other_plan_sub_item].each(&:reload)

        assert_predicate unpaid_sub_item, :active?, "unpaid sub item should remain active"
        assert_predicate other_plan_sub_item, :active?, "sub item for other plan should remain active"

        [paid_sub_item1, paid_sub_item2].each do |sub_item|
          assert_predicate sub_item, :cancelled?, "paid sub items for this subscription should be cancelled"
        end
      end

      test "does not enqueue synchronization when skip_sync is true" do
        general_purpose_plan = create(:billing_plan_subscription)
        paid_sub_item = create(:billing_subscription_item, :paid,
          plan_subscription: general_purpose_plan,
        )

        assert_predicate paid_sub_item, :active?, "sub item should be active before cancellation"

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          general_purpose_plan.cancel_subscription_items!(skip_sync: true)
        end

        assert_predicate paid_sub_item.reload, :cancelled?, "sub item should be cancelled"
      end
    end

    context "#subscription_item_for_marketplace_listing" do
      test "returns last active subscription item for marketplace listing" do
        user = create(:user)
        org = create(:credit_card_org, admin: user)
        plan_subscription = create(:billing_plan_subscription, user: org)

        listing_plan = create(:marketplace_listing_plan, :verified_listing)

        subscription_item = create :billing_subscription_item,
          plan_subscription: plan_subscription,
          subscribable: listing_plan,
          quantity: 1

        assert_equal subscription_item, plan_subscription.subscription_item_for_marketplace_listing(listing_plan.listing)
      end

      test "returns nil if marketplace listing has no active subscription items" do
        user = create(:user)
        org = create(:credit_card_org, admin: user)
        plan_subscription = create(:billing_plan_subscription, user: org)

        listing_plan = create(:marketplace_listing_plan, :verified_listing)

        assert_nil plan_subscription.subscription_item_for_marketplace_listing(listing_plan.listing)
      end

      context "self-serve payment enterprise account orgs" do
        test "returns last active subscription item for marketplace listing" do
          business = create :business, :with_self_serve_payment
          org1 = create :organization, business: business
          org2 = create :organization, business: business

          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer
          listing_plan = create(:marketplace_listing_plan, :verified_listing)
          subscription_item_org1 = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: listing_plan,
            quantity: 1,
            organization: org1

          subscription_item_org2 = create :billing_subscription_item,
            plan_subscription: plan_subscription,
            subscribable: listing_plan,
            quantity: 1,
            organization: org2

          assert_equal subscription_item_org1, plan_subscription.subscription_item_for_marketplace_listing(listing_plan.listing, organization: org1)
          assert_equal subscription_item_org2, plan_subscription.subscription_item_for_marketplace_listing(listing_plan.listing, organization: org2)
        end
      end
    end

    context "#subscription_item_for_sponsors_listing" do
      test "returns last active subscription item for Sponsors listing" do
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        sponsorship = create(:sponsorship, tier: tier)
        plan_subscription = sponsorship.plan_subscription
        subscription_item = sponsorship.subscription_item

        assert_equal subscription_item, plan_subscription.subscription_item_for_sponsors_listing(tier.sponsors_listing)
      end

      test "returns active subscription item for Sponsors listing when sponsorship was paid for via sponsorship-specific Zuora account" do
        invoiced_org = create(:invoiced_organization, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        sponsorship = create(:sponsorship, sponsor: invoiced_org)
        subscription_item = sponsorship.subscription_item
        sponsors_listing = sponsorship.sponsors_listing
        plan_subscription = invoiced_org.sponsors_plan_subscription

        assert_equal subscription_item, plan_subscription.subscription_item_for_sponsors_listing(sponsors_listing)
      end

      test "returns active one-time subscription item for Sponsors listing when recurring subscription item is inactive" do
        one_time_tier = create(:sponsors_tier, :approved_sponsors_listing, :one_time)
        one_time_sponsorship = create(:sponsorship, tier: one_time_tier)
        plan_subscription = one_time_sponsorship.plan_subscription
        listing = one_time_tier.sponsors_listing
        recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)
        create(:sponsors_subscription_item, plan_subscription: plan_subscription, subscribable: recurring_tier,
          quantity: 0)

        one_time_active_sub_item = one_time_sponsorship.subscription_item

        assert_equal one_time_active_sub_item, plan_subscription.subscription_item_for_sponsors_listing(listing)
      end

      test "returns active subscription item for recurring tier for Sponsors listing if there are also active subscription items for one-time tiers" do
        listing = create(:sponsors_listing, :approved, tier_count: 1, one_time_tier_count: 2)
        recurring_tier = listing.published_sponsors_tiers.recurring.first
        recurring_sponsorship = create(:sponsorship, tier: recurring_tier)
        plan_subscription = recurring_sponsorship.plan_subscription
        one_time_tier1 = listing.published_sponsors_tiers.one_time.first
        one_time_sub_item = create(:sponsors_subscription_item, subscribable: one_time_tier1, plan_subscription: plan_subscription, quantity: 1)
        recurring_sub_item = recurring_sponsorship.subscription_item
        assert_same_elements [one_time_sub_item, recurring_sub_item],
          listing.active_subscription_items,
          "need multiple subscription items active for the listing at once from the same plan subscription"

        assert_equal recurring_sub_item, plan_subscription.subscription_item_for_sponsors_listing(listing)
      end

      test "returns nil if Sponsors listing has no subscription items at all" do
        plan_subscription = create(:billing_plan_subscription)
        tier = create(:sponsors_tier, :approved_sponsors_listing)

        assert_nil plan_subscription.subscription_item_for_sponsors_listing(tier.sponsors_listing)
      end

      test "returns nil if Sponsors listing has only inactive subscription items" do
        plan_subscription = create(:billing_plan_subscription)
        tier = create(:sponsors_tier, :approved_sponsors_listing)
        create(:sponsorship, :inactive, tier: tier, sponsor: plan_subscription.user)

        assert_nil plan_subscription.subscription_item_for_sponsors_listing(tier.sponsors_listing)
      end
    end

    context ".create" do
      test "synchronizes the subscription in a background job" do
        user = create(:credit_card_user, plan: "free")

        assert_enqueued_with(
          job: SynchronizePlanSubscriptionJob,
          args: [{ user_id: user.id, plan_name: user.plan.name, purpose: "general" }, user: user]
        ) do
          create(:billing_plan_subscription, user: user)
        end
      end

      test "creates a Zuora subscription" do
        user = create(:credit_card_user, plan: "free")
        only = [SynchronizePlanSubscriptionJob]
        plan_subscription = perform_enqueued_jobs(only: only) do
          create(:billing_plan_subscription, user: user)
        end
        plan_subscription.reload

        assert plan_subscription.zuora_subscription
      end

      test "creates a Zuora subscription with seats" do
        user = create(:credit_card_user, plan: "business", seats: 10)
        only = [SynchronizePlanSubscriptionJob]
        plan_subscription = perform_enqueued_jobs(only: only) do
          create(:billing_plan_subscription, user: user)
        end
        plan_subscription.reload
        assert plan_subscription.zuora_subscription
      end

      test "validates uniqueness on user_id" do
        user = create(:credit_card_user, plan: "free")

        create(:billing_plan_subscription, user: user)

        assert_raises ActiveRecord::RecordInvalid do
          create(:billing_plan_subscription, user: user)
        end
      end

      test "requires a unique user per purpose" do
        plan_sub1 = create(:billing_plan_subscription)
        plan_sub2 = Billing::PlanSubscription.new(purpose: plan_sub1.purpose, user: plan_sub1.user)
        refute_predicate plan_sub2, :valid?
        assert_includes plan_sub2.errors[:user_id], "already has a plan subscription for that purpose"
      end

      test "allows a user to have a plan subscription of each purpose" do
        plan_sub1 = create(:billing_plan_subscription, purpose: :general)
        customer2 = create(:customer, :sponsors_invoiced)
        plan_sub2 = build(:billing_plan_subscription, purpose: :sponsors, user: plan_sub1.user,
          customer: customer2)
        assert_predicate plan_sub2, :valid?
      end

      test "allows Sponsors-specific plan subscription for general-purpose customer when no Sponsors-specific customer exists" do
        user = create(:credit_card_user)
        customer = user.customer
        assert_predicate customer, :general_purpose?, "need a general-purpose Customer"

        plan_sub = Billing::PlanSubscription.new(purpose: :sponsors, customer: customer, user: user)

        assert_predicate plan_sub, :valid?
      end

      # https://github.com/github/sponsors/issues/4928
      test "disallows active, Sponsors-specific plan subscription for general-purpose customer when a Sponsors-specific customer exists and feature is enabled" do
        org = create(:invoiced_organization, :sponsors_invoiced)
        general_customer = org.customer
        assert_predicate general_customer, :general_purpose?, "need a general-purpose Customer"

        plan_sub = build(:billing_plan_subscription, :zuora, purpose: :sponsors, customer: general_customer,
          user: org)

        refute_predicate plan_sub, :valid?
        assert_includes plan_sub.errors[:base], "An active Sponsors-specific plan subscription must be tied to the " \
          "account's Sponsors-specific customer when one exists."
      end

      test "disallows general-purpose plan subscription for Sponsors-specific customer" do
        customer = create(:customer, :sponsors_invoiced)
        assert_predicate customer, :sponsors_purpose?, "need a Sponsors-specific Customer"

        plan_sub = Billing::PlanSubscription.new(purpose: :general, customer: customer)

        refute_predicate plan_sub, :valid?
        assert_includes plan_sub.errors[:purpose], "must be sponsors to match customer"
      end

      test "defaults to the user's plan duration" do
        user = create :credit_card_user,
          plan: "pro",
          plan_duration: "month"
        plan_subscription = create(:billing_plan_subscription,
                                   :zuora, user: user)
        product_uuid = create(
          :billing_product_uuid,
          :github_plan,
          product_key: "pro",
        )
        create_zuora_subscription(
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: {
            "account_key" => "suspended-zuora-subscription",
            "subscribeToRatePlans" => [{
              "productRatePlanId" => product_uuid.zuora_product_rate_plan_id,
              "chargeOverrides" => [],
            }],
          },
        )

        zuora_subscription = user.reload.plan_subscription.zuora_subscription
        assert plan_subscription.persisted?
        assert_equal "pro", zuora_subscription.plan.name
        assert_equal "month", zuora_subscription.plan_duration
      end
    end

    context "#retry_charge" do
      test "doesn't run for users outside of dunning" do
        user = create(:user, :zuora)
        user.customer.update  \
          zuora_account_id: "2c92c0f8634398fc016350c3c8482456"
        plan_subscription = create :billing_plan_subscription, :zuora,
          user: user, customer: user.customer
        expected_payload = {
          "code.function" => "retry_charge",
          "gh.billing.billable_entity.id" => user.id,
          "gh.billing.billable_entity.type" => user.class.name,
          "gh.billing.billable_entity.dunning" => user.dunning?
        }

        GitHub.zuorest_client.expects(:create_subscription).never

        assert_logged(**expected_payload) do
          result = plan_subscription.retry_charge

          assert result.success?
        end
      end

      test "doesn't run for businesses outside dunning" do
        business = create(:business, :with_self_serve_payment)
        business.customer.update  \
          zuora_account_id: "2c92c0f8634398fc016350c3c8482456"
        plan_subscription = create :billing_plan_subscription, :zuora,
          user: nil, customer: business.customer
        expected_payload = {
          "code.function" => "retry_charge",
          "gh.billing.billable_entity.id" => business.id,
          "gh.billing.billable_entity.type" => business.class.name,
          "gh.billing.billable_entity.dunning" => business.dunning?
        }

        GitHub.zuorest_client.expects(:create_subscription).never

        assert_logged(**expected_payload) do
          result = plan_subscription.retry_charge

          assert result.success?
        end
      end

      test "success for user w/ active Sponsors-specific plan subscription" do
        user = create(:credit_card_user, :verified, plan_duration: "year")
        customer = user.customer
        customer.update!(
          zuora_account_id: "8ad08d2986bb64550186befc32945e75",
          zuora_account_number: "A0102179575",
        )

        with_live_zuora("zuora/retry_charge_apm") do
          sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 1_00)
          sponsors_tier.sponsors_listing.sync_to_zuora
          sponsorship = create(:sponsorship, tier: sponsors_tier, sponsor: user)
          sponsors_plan_subscription = sponsorship.plan_subscription

          synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_subscription, false,
            collect: false, # avoid collecting to fake out a failed payment
          )
          result = synchronizer.create

          user.update_column :billing_attempts, 1
          sponsors_plan_subscription.reload

          result = sponsors_plan_subscription.retry_charge

          assert_predicate result, :success?
        end
      end

      test "success for user w/ only general plan subscription" do
        user = create(:user, :zuora)
        customer = user.customer
        customer.update  \
          zuora_account_id: "2c92c0fb647e2f050164866a3da717d2"
        plan_subscription = create :billing_plan_subscription, :zuora,
          user: user, customer: customer
        user.update_column :billing_attempts, 1

        assert_nil customer.sponsors_plan_subscription

        with_live_zuora("zuora/retry_charge") do
          result = plan_subscription.retry_charge

          assert_predicate result, :success?
          assert_equal 0, plan_subscription.zuora_account["metrics"]["balance"]
        end
      end
    end

    context "#synchronize" do
      test "creates a new subscription when one does not exist" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.reload

        PlanSubscription::Synchronizer
          .expects(:create)
          .with(plan_subscription, anything, has_key(:synchronization_id))
          .returns(GitHub::Billing::Result.success)

        assert plan_subscription.synchronize.success?
      end

      test "does not create an external subscription when on the free plan" do
        PlanSubscription::Synchronizer.expects(:update).never
        PlanSubscription::Synchronizer.expects(:create).never

        user = create(:user, plan: "free")
        plan_subscription = create(:billing_plan_subscription, user: user)

        plan_subscription.synchronize
      end

      test "creates a new subscription for Sponsors invoiced org" do
        invoiced_org = create(:invoiced_organization, plan: GitHub::Plan.free_with_addons)

        sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced, payment_method_user: invoiced_org)
        create(:customer_account, :sponsors_invoiced, customer: sponsors_customer, user: invoiced_org)
        sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: invoiced_org)

        PlanSubscription::Synchronizer.expects(:create).once
          .with(sponsors_plan_sub, anything, has_key(:synchronization_id))
          .returns(GitHub::Billing::Result.success)
        sponsors_plan_sub.synchronize
      end

      test "does not create braintree subscription when no payment amount" do
        PlanSubscription::Synchronizer.expects(:create).never

        user = create(:user, plan: "pro")
        user.redeem_coupon create(:coupon, discount: 2000)
        plan_subscription = create(:billing_plan_subscription, user: user)

        plan_subscription.synchronize
      end

      test "does not create a subscription when payment method is cleared" do
        PlanSubscription::Synchronizer.expects(:update).never
        PlanSubscription::Synchronizer.expects(:create).never

        user = create(:no_credit_card_user, plan: GitHub::Plan.free_with_addons)
        user.customer.update!(
          payment_method: create(:payment_method, payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED),
        )

        plan_subscription = create(:billing_plan_subscription, user: user)
        assert plan_subscription.synchronize.success?
      end

      test "logs synchronization success with a Zuora subscription" do
        plan_subscription = create :billing_plan_subscription,
          user: create(:user, :zuora, plan: "pro")
        events = subscribe("plan_subscription.synchronize")
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Billing::PlanSubscription::Synchronizer
          .expects(:create)
          .returns(GitHub::Billing::Result.success)

        plan_subscription.synchronize

        expected_payload = {
          external_subscription_type: "zuora",
          success: true,
          collect: nil,
          plan_subscription_id: plan_subscription.id,
          plan: plan_subscription.user.plan.name,
          seats: plan_subscription.user.seats,
          user: plan_subscription.user.login,
          user_id: plan_subscription.user.id,
          purpose: "general",
          synchronization_action: "create",
        }
        actual_payload = events.pop.payload
        assert_equal expected_payload, actual_payload.except(:synchronization_id)
        assert actual_payload[:synchronization_id]

        # Verify that we've incremented our dogstats counter
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:true"]).count
      end

      test "logs update synchronization success with a Zuora subscription" do
        user = create(:user, :zuora, plan: "pro")
        plan_subscription = create :billing_plan_subscription, :zuora, user: user
        events = subscribe("plan_subscription.synchronize")
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        Billing::PlanSubscription::Synchronizer
          .expects(:update)
          .returns(GitHub::Billing::Result.success)

        plan_subscription.synchronize

        expected_payload = {
          external_subscription_type: "zuora",
          success: true,
          collect: nil,
          plan_subscription_id: plan_subscription.id,
          plan: user.plan.name,
          seats: user.seats,
          user: plan_subscription.user.login,
          user_id: plan_subscription.user.id,
          purpose: "general",
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          synchronization_action: "update",
        }
        actual_payload = events.pop.payload
        assert_equal expected_payload, actual_payload.except(:synchronization_id)
        assert actual_payload[:synchronization_id]

        # Verify that we've incremented our dogstats counter
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:true"]).count

        # Check SubscriptionSyncStatus update
        subscription_sync_status = plan_subscription.subscription_sync_statuses.first
        assert_equal subscription_sync_status.external_sync_status, "success"
      end

      test "logs synchronization failure with a Zuora subscription and raises" do
        plan_subscription = create :billing_plan_subscription,
          user: create(:user, :zuora, plan: "pro")
        events = subscribe("plan_subscription.synchronize")
        subscription_sync_status = SubscriptionSyncStatus.create(target: plan_subscription.user, external_sync_status: :pending)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        zuora_response = { "Success" => false, "reasons" => [{ "message" => "I'm sorry, Dave. I'm afraid I can't do that." }] }
        Billing::PlanSubscription::Synchronizer
          .expects(:create)
          .returns(GitHub::Billing::Result.from_zuora(zuora_response))

        attempts_per_exception = { "[Billing::Zuora::SynchronizationError]" => 4 }
        assert_raises Billing::Zuora::SynchronizationError do
          plan_subscription.synchronize(attempts_per_exception: attempts_per_exception)
        end

        expected_payload = {
          synchronization_action: "create",
          attempts_per_exception: attempts_per_exception,
          error: "I'm sorry, Dave. I'm afraid I can't do that.",
          external_result: zuora_response,
          external_subscription_type: "zuora",
          plan_subscription_id: plan_subscription.id,
          success: false,
          collect: nil,
          plan: plan_subscription.user.plan.name,
          seats: plan_subscription.user.seats,
          user: plan_subscription.user.login,
          user_id: plan_subscription.user.id,
          purpose: "general",
        }
        actual_payload = events.pop.payload
        assert_equal expected_payload, actual_payload.except(:synchronization_id)
        assert actual_payload[:synchronization_id]

        # Verify that we've incremented our dogstats counter
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"]).count

        # Check SubscriptionSyncStatus update
        subscription_sync_status = SubscriptionSyncStatus.find_by!(target: plan_subscription.user)
        assert_equal subscription_sync_status.external_sync_status, "failure"
        assert_equal subscription_sync_status.number_of_retries_remaining, 0
      end

      test "logs synchronization failure with a Zuora subscription and DOES NOT raise for declines" do
        plan_subscription = create :billing_plan_subscription,
          user: create(:user, :zuora, plan: "pro")
        events = subscribe("plan_subscription.synchronize")
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        zuora_response = { "Success" => false, "reasons" => [{ "message" => "declined payment" }] }
        Billing::PlanSubscription::Synchronizer
          .expects(:create)
          .returns(GitHub::Billing::Result.from_zuora(zuora_response))

        # Implied assertion: does not raise
        plan_subscription.synchronize

        expected_payload = {
          synchronization_action: "create",
          attempts_per_exception: {},
          error: "declined payment",
          external_result: zuora_response,
          external_subscription_type: "zuora",
          plan_subscription_id: plan_subscription.id,
          success: false,
          collect: nil,
          plan: "pro",
          seats: plan_subscription.user.seats,
          user: plan_subscription.user.login,
          user_id: plan_subscription.user.id,
          purpose: "general",
        }
        actual_payload = events.pop.payload
        assert_equal expected_payload, actual_payload.except(:synchronization_id)
        assert actual_payload[:synchronization_id]

        # Verify that we've incremented our dogstats counter
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"]).count
      end

      test "doesn't synchronize invoiced customers" do
        org = create :organization, :zuora, billing_type: "invoice"
        plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
        events = subscribe("plan_subscription.synchronize")
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        plan_subscription.synchronize

        assert_empty events
        assert_empty GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"])
      end

      test "attaches purpose-specific plan subscriptions to the correct Zuora subscription for a user" do
        sponsors_listing = create(:sponsors_listing, :approved, :with_uuids)
        user = create(:user, :zuora, plan: "pro")
        customer = user.customer

        sponsors_plan_subscription = create(:billing_plan_subscription, :zuora, :sponsors_invoiced, user: user, customer: customer)
        sponsorship = create(:sponsorship, sponsor: user, sponsorable: sponsors_listing.sponsorable)
        sponsors_plan_subscription.subscription_items << sponsorship.subscription_item
        general_plan_subscription = create(:billing_plan_subscription, :zuora, user: user, customer: customer)

        zuora_account = customer.zuora_account
        customer.update!(zuora_account_id: zuora_account.id)
        stub_sponsors_subscriptions(zuora_account: zuora_account, plan_subscriptions: user.plan_subscriptions.to_a, separate_subscriptions: true)

        sponsors_plan_subscription_number = sponsors_plan_subscription.zuora_subscription_number
        general_plan_subscription_number = general_plan_subscription.zuora_subscription_number

        sponsors_plan_subscription.update!(zuora_subscription_number: nil)
        general_plan_subscription.update!(zuora_subscription_number: nil)
        assert_nil sponsors_plan_subscription.reload.zuora_subscription_number
        sponsors_plan_subscription.attach_orphaned_zuora_subscription
        assert_equal sponsors_plan_subscription_number, sponsors_plan_subscription.reload.zuora_subscription_number
        assert_nil general_plan_subscription.reload.zuora_subscription_number

        sponsors_plan_subscription.update!(zuora_subscription_number: nil)
        general_plan_subscription.update!(zuora_subscription_number: nil)
        assert_nil general_plan_subscription.reload.zuora_subscription_number
        general_plan_subscription.attach_orphaned_zuora_subscription
        assert_nil sponsors_plan_subscription.reload.zuora_subscription_number
        assert_equal general_plan_subscription_number, general_plan_subscription.reload.zuora_subscription_number
      end

      test "enqueues a skipped line items update job on a newly synchronized subscription" do
        plan_subscription = create :billing_plan_subscription, user: create(:user, :zuora, plan: "pro")

        Billing::PlanSubscription::Synchronizer
          .expects(:create)
          .returns(GitHub::Billing::Result.success)

        assert_enqueued_with(job: ::Billing::UpdateSkippedMeteredLineItemsJob, args: [{ billable_owner: plan_subscription.user }]) do
          plan_subscription.synchronize
        end
      end

      test "enqueues a skipped line item update job on an synchronized existing subscription" do
        user = create(:user, :zuora, plan: "pro")
        plan_subscription = create :billing_plan_subscription, :zuora, user: user
        Billing::PlanSubscription::Synchronizer
          .expects(:update)
          .returns(GitHub::Billing::Result.success)

        assert_enqueued_with(job: ::Billing::UpdateSkippedMeteredLineItemsJob, args: [{ billable_owner: plan_subscription.user }]) do
          plan_subscription.synchronize
        end
      end

      test "does not enqueue a skilled line item update job when synchronization fails" do
        plan_subscription = create :billing_plan_subscription, user: create(:user, :zuora, plan: "pro")

        zuora_response = { "Success" => false, "reasons" => [{ "message" => "declined payment" }] }
        Billing::PlanSubscription::Synchronizer
          .expects(:create)
          .returns(GitHub::Billing::Result.from_zuora(zuora_response))

        assert_no_enqueued_jobs(only: ::Billing::UpdateSkippedMeteredLineItemsJob) do
          plan_subscription.synchronize
        end
      end
    end

    context "#destroy" do
      test "cancels the zuora subscription and zeros out invoices when triggered by user destroy" do
        with_live_zuora("zuora/close_zuora_subscription_on_destroy") do
          plan = GitHub::Plan.pro

          user = create(:user, plan: plan)
          zuora_successful_customer_account_creation(user)
          user.reload

          plan_subscription = user.plan_subscription
          sub_number = "A-S00005148"
          plan_subscription.update_column(:zuora_subscription_number, sub_number)

          invoices = Billing::Zuora::Invoice.invoices_for_subscription(sub_number)

          refute_nil plan_subscription.zuora_subscription_number
          refute_equal 0, T.must(invoices.first).balance

          user.destroy

          assert_raises ActiveRecord::RecordNotFound do
            plan_subscription.reload
          end
        end

        # VCR was replaying the previous invoices call, hence the need for a new
        # cassette --> thanks @tonkpils for solving this!
        with_live_zuora("zuora/close_zuora_subscription_on_destroy_part_two") do
          sub_number = "A-S00005148"
          invoices = Billing::Zuora::Invoice.invoices_for_subscription(sub_number)

          assert_equal 0, T.must(invoices.first).balance
        end
      end

      test "destroys all associated subscription sync statuses" do
        user = create(:user, plan: GitHub::Plan.pro)
        plan_subscription = create(:billing_plan_subscription, user: user)
        create(:billing_subscription_sync_status, target: user, plan_subscription: plan_subscription)
        create(:billing_subscription_sync_status, target: user, plan_subscription: plan_subscription)

        refute_empty SubscriptionSyncStatus.where(target: user)

        plan_subscription.destroy

        assert_empty SubscriptionSyncStatus.where(target: user)
      end

      test "does not raise an exception if the user no longer exists" do
        plan_subscription = create :billing_plan_subscription
        plan_subscription.user.delete

        plan_subscription.reload.destroy
      end

      test "enqueue a job to close the zuora subscription" do
        plan_subscription = create(:billing_plan_subscription, :zuora)

        assert_enqueued_with job: CloseOutZuoraSubscriptionJob, args: [{ zuora_subscription_number: plan_subscription.zuora_subscription_number }] do
          plan_subscription.destroy
        end
      end
    end

    context "#plan_synchronized?" do
      test "true if plan is free with addons on and Zuora subscription plan is nil" do
        # Zuora does not have a rate plan for free with addons and does not return a plan for that case
        with_live_zuora("zuora/subscriptions/free_with_addons") do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create :marketplace_listing_plan, :published,
            per_unit: true,
            unit_name: "Seats",
            listing: listing
          listing_plan.sync_to_zuora
          user = create(:user, plan: GitHub::Plan.free_with_addons)
          zuora_successful_customer_account_creation(user)
          user.customer.update!(bill_cycle_day: 0)
          user.reload
          plan_subscription = user.plan_subscription
          create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4
          Billing::PlanSubscription::ZuoraSynchronizer.create(plan_subscription.reload)
          user.reload

          zuora_subscription = user.plan_subscription.zuora_subscription

          assert_nil zuora_subscription.plan
          assert_equal GitHub::Plan.free_with_addons, user.plan

          assert user.plan_subscription.plan_synchronized?
        end
      end
    end

    context "#synchronized?" do
      test "true if PlanSubscription and Zuora subscription are in sync" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create :billing_plan_subscription, user: user
        plan_subscription.synchronize
        plan_subscription.reload
        fake_subscription_charged_successfully_webhook(plan_subscription)
        assert plan_subscription.synchronized?
      end

      test "false if the plan is out of sync" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create :billing_plan_subscription, user: user
        plan_subscription.synchronize
        plan_subscription.reload
        zuora_id = plan_subscription.zuora_subscription_number

        fake_subscription_charged_successfully_webhook(plan_subscription)
        assert plan_subscription.synchronized?

        # Update the external subscription and then reset the variable so it's
        # pulled again
        subscription = T.must(FakestZuora.registry.find(:subscription, zuora_id))
        T.must(subscription.rate_plans.first)[:productRatePlanId] = "wrong_id"

        plan_subscription.reload

        refute_predicate plan_subscription, :plan_synchronized?
        refute_predicate plan_subscription, :synchronized?
      end

      test "false if plan_duration is out of sync" do
        user = create :user, :zuora, plan: "pro"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize
        plan_subscription.reload
        zuora_id = plan_subscription.zuora_subscription_number

        # Update the external subscription and then reset the variable so it's
        # pulled again
        subscription = T.must(FakestZuora.registry.find(:subscription, zuora_id))
        subscription.rate_plans.each do |plan|
          plan[:ratePlanCharges].each { |charge| charge[:billingPeriod] = "Annual" }
        end
        plan_subscription.instance_variable_set(:@fetched_external_subscription, nil)

        refute plan_subscription.plan_duration_synchronized?
        refute plan_subscription.synchronized?
      end

      test "false if seats are out of sync" do
        user = create :user, :zuora, plan: "business", seats: "10"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize
        zuora_id = plan_subscription.zuora_subscription_number

        fake_subscription_charged_successfully_webhook(plan_subscription)
        plan_subscription.reload
        assert plan_subscription.synchronized?

        # Update the external subscription and then reset the variable so it's
        # pulled again
        plan = T.must(T.must(FakestZuora.registry.find(:subscription, zuora_id)).rate_plans.first)
        plan[:ratePlanCharges].first[:quantity] = "20"
        plan_subscription.instance_variable_set(:@fetched_external_subscription, nil)

        refute plan_subscription.reload.seats_synchronized?
        refute plan_subscription.synchronized?
      end

      test "true if additional seats for tiered per seat plan are in sync" do
        user = create :user, :zuora, plan: "business", seats: "10"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize

        fake_subscription_charged_successfully_webhook(plan_subscription)
        assert plan_subscription.reload.synchronized?
      end

      test "true if seats are out of sync but user is on a repo plan" do
        user = create :user, :zuora, plan: "bronze"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize

        fake_subscription_charged_successfully_webhook(plan_subscription)

        plan_subscription.user.seats = 10

        assert plan_subscription.reload.seats_synchronized?
        assert plan_subscription.synchronized?
      end

      test "false if data packs are out of sync" do
        user = create(:credit_card_user, plan: "pro")
        Asset::Status.create(owner: user, asset_packs: 10)
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize
        zuora_id = user.reload.plan_subscription.zuora_subscription_number

        fake_subscription_charged_successfully_webhook(plan_subscription)

        assert plan_subscription.synchronized?

        lfs_product = Billing::ProductUUID.find_by!(
          product_type: "github.lfs",
          product_key: "v0",
          billing_cycle: user.plan_duration,
        )

        # Update the external subscription and then reset the variable so it's
        # pulled again
        plans = T.must(FakestZuora.registry.find(:subscription, zuora_id)).rate_plans
        lfs_plan = T.must(plans.detect do
          |plan| plan[:productRatePlanId] == lfs_product.zuora_product_rate_plan_id
        end)
        lfs_plan[:ratePlanCharges].first[:quantity] = "20"
        plan_subscription.instance_variable_set(:@fetched_external_subscription, nil)

        refute plan_subscription.reload.asset_packs_synchronized?
        refute plan_subscription.synchronized?
      end

      test "false if discount is out of sync" do
        user = create :credit_card_user, plan: "pro", plan_duration: "year"
        coupon = create(:coupon, discount: 5)
        coupon.sync_to_zuora
        user.redeem_coupon coupon
        plan_subscription = create(:billing_plan_subscription, user: user)
        user.customer.update!(bill_cycle_day: user.billed_on.day)
        plan_subscription.synchronize
        plan_subscription.reload
        zuora_id = plan_subscription.zuora_subscription_number

        fake_subscription_charged_successfully_webhook(plan_subscription)

        assert plan_subscription.reload.synchronized?

        # Update the external subscription and then reset the variable so it's
        # pulled again
        coupon_product = Billing::ProductUUID.find_by!(
          product_type: "github.coupon",
          product_key: "fixed_amount",
          billing_cycle: user.plan_duration,
        )
        plans = T.must(FakestZuora.registry.find(:subscription, zuora_id)).rate_plans
        coupon_plan = T.must(plans.detect do |plan|
          plan[:productRatePlanId] == coupon_product.zuora_product_rate_plan_id
        end)
        coupon_plan[:ratePlanCharges].first[:discountAmount] = 10.0
        plan_subscription.reload

        refute_predicate plan_subscription, :discount_synchronized?
        refute_predicate plan_subscription, :synchronized?
      end

      test "correctly compares zuoura subscription balances" do
        user = create :credit_card_user, plan: "pro"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize
        # Balance returns a float rather than a BigDecimal
        Billing::Zuora::Subscription.any_instance.stubs(:balance).returns(Float("-96.68"))

        fake_subscription_charged_successfully_webhook(plan_subscription)
        plan_subscription.update_attribute(:balance_in_cents, -96_68)

        assert plan_subscription.balance_synchronized?
        assert plan_subscription.synchronized?
      end

      test "false if balance is out of sync" do
        user = create :credit_card_user, plan: "pro"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize
        Billing::Subscription.any_instance.stubs(:balance).returns(BigDecimal("-80.10"))

        refute plan_subscription.synchronized?

        fake_subscription_charged_successfully_webhook(plan_subscription)
        plan_subscription.update_attribute(:balance_in_cents, -80_10)
        plan_subscription.synchronize
        assert plan_subscription.synchronized?
      end

      test "false if the next billing date out of sync" do
        user = create :credit_card_user, plan: "pro", plan_duration: "year"
        plan_subscription = create(:billing_plan_subscription, user: user)
        plan_subscription.synchronize

        plan_subscription.user.update_attribute(:billed_on, GitHub::Billing.today + 1.month)
        plan_subscription.reload

        refute plan_subscription.next_billing_date_synchronized?
        refute plan_subscription.synchronized?
      end

      test "false when there is no zuora subscription" do
        user = create :credit_card_user, plan: "free"
        plan_subscription = create :billing_plan_subscription,
          user: user,
          zuora_subscription_number: nil

        refute plan_subscription.synchronized?
      end
    end

    context "#zuora_params" do
      test "returns zuora subscription params object" do
        subscription_params = Billing::PlanSubscription::ZuoraSubscriptionParams
        assert_kind_of subscription_params, build(:billing_plan_subscription, :zuora).zuora_params
      end
    end

    context "#external_subscription_type" do
      test "is zuora for Zuora subscriptions" do
        plan_subscription = PlanSubscription.new(zuora_subscription_number: "A-S#{rand(100000)}")

        assert_equal "zuora", plan_subscription.external_subscription_type
      end

      test "is nil when the subscription is not managed externally" do
        plan_subscription = PlanSubscription.new

        refute plan_subscription.external_subscription_type
      end
    end

    context "#on_free_trial?" do
      test "reloads the user after checking the trial status to avoid charging customer for trial plan rather than chosen plan in race condition" do
        organization = create(:credit_card_org, plan: "free", seats: 0)
        Billing::EnterpriseCloudTrial.new(organization).create

        plan_subscription = create(:billing_plan_subscription, user: organization)
        assert_equal "business_plus", plan_subscription.user.plan.name
        assert_equal 50, plan_subscription.user.seats

        # Simulate a differnt process updating the organization's plan and seats
        Organization.find(organization.id).update!(plan: "business", seats: 10)

        assert plan_subscription.on_free_trial?
        assert_equal "business", plan_subscription.user.plan.name
        assert_equal 10, plan_subscription.user.seats
      end

      test "returns false for a trial business whose trial conversion has been initiated" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = plan_subscription.business
        business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        business.initiate_trial_conversion

        assert_predicate business, :trial?
        assert_predicate business, :trial_conversion_initiated?
        refute_predicate plan_subscription.reload, :on_free_trial?
      end

      test "returns false for a trial business who has been flagged into RBI" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = plan_subscription.business
        business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)
        business.disable_auto_pay!(:india_rbi)

        assert_equal business.trial_completion_status.to_sym, :no_trial_or_active_trial
        assert_predicate business, :trial?
        assert_predicate business, :autopay_disabled_by_india_rbi?
        refute_predicate plan_subscription.reload, :on_free_trial?
      end

      test "returns true for a trial business whose trial conversion has not been initiated" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = plan_subscription.business
        business.update_attribute(:trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now)

        assert_predicate business, :trial?
        refute_predicate business, :trial_conversion_initiated?
        assert_predicate plan_subscription.reload, :on_free_trial?
      end

      test "returns false for a non-trial business" do
        plan_subscription = create(:billing_plan_subscription, :business_owned)
        business = plan_subscription.business

        refute_predicate business, :trial?
        refute_predicate plan_subscription, :on_free_trial?
      end
    end

    context "#apple_iap_subscription?" do
      test "returns true for an apple iap subscription" do
        plan = create(:billing_plan_subscription, :apple_iap)

        assert plan.apple_iap_subscription?
      end

      test "returns false for all other subscriptions" do
        plan = create(:billing_plan_subscription)

        refute plan.apple_iap_subscription?
      end
    end

    context "#cancelled_or_non_zuora?" do
      test "true when there is no Zuora subscription information and no rate plans charges" do
        plan_subscription = build(:billing_plan_subscription, zuora_subscription_id: nil,
          zuora_subscription_number: nil, zuora_rate_plan_charges: {})
        assert_predicate plan_subscription, :cancelled_or_non_zuora?
      end

      test "false when Zuora subscription ID is present" do
        plan_subscription = build(:billing_plan_subscription, zuora_subscription_id: SecureRandom.hex(16),
          zuora_subscription_number: nil, zuora_rate_plan_charges: {})
        refute_predicate plan_subscription, :cancelled_or_non_zuora?
      end

      test "false when Zuora subscription number is present" do
        plan_subscription = build(:billing_plan_subscription, zuora_subscription_id: nil,
          zuora_subscription_number: "A-S#{SecureRandom.hex(6)}", zuora_rate_plan_charges: {})
        refute_predicate plan_subscription, :cancelled_or_non_zuora?
      end

      test "false when Zuora rate plan charges are present" do
        rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
        plan_subscription = create(
          :billing_plan_subscription, zuora_subscription_id: nil,
          zuora_subscription_number: nil,
          zuora_rate_plan_charges: {
            rate_plan_charge[:productRatePlanChargeId] => {
              number: rate_plan_charge[:number],
              charged_through_date: Date.parse(rate_plan_charge[:chargedThroughDate])
            }
          }
        )
        create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_subscription, payload: rate_plan_charge)
        refute_predicate plan_subscription, :cancelled_or_non_zuora?
      end
    end

    context "#unsynced_with_zuora?" do
      test "true when zuora subscription id or number are nil" do
        unsynced_plan = create(:billing_plan_subscription, zuora_subscription_id: nil, zuora_subscription_number: nil)
        plan_without_id = create(:billing_plan_subscription, :zuora, zuora_subscription_id: nil)
        plan_without_number = create(:billing_plan_subscription, :zuora, zuora_subscription_number: nil)

        assert_predicate unsynced_plan, :unsynced_with_zuora?
        assert_predicate plan_without_id, :unsynced_with_zuora?
        assert_predicate plan_without_number, :unsynced_with_zuora?
      end

      test "false when a zuora subscription id and number exists" do
        plan_with_both = create(:billing_plan_subscription, :zuora)

        refute_predicate plan_with_both, :unsynced_with_zuora?
      end
    end

    context "#general_purpose_customer?" do
      test "true when customer has purpose=general" do
        general_plan_sub = create(:billing_plan_subscription)
        user = general_plan_sub.user
        customer = general_plan_sub.customer
        sponsors_plan_sub = create(:billing_plan_subscription, user: user, purpose: :sponsors)
        assert_predicate customer, :general_purpose?, "expected general-purpose customer"

        assert_predicate general_plan_sub, :general_purpose_customer?
        assert_predicate sponsors_plan_sub, :general_purpose_customer?
      end

      test "false when customer has purpose=sponsors" do
        sponsors_plan_sub_with_sponsors_customer = create(:billing_plan_subscription, :sponsors_invoiced)
        customer = sponsors_plan_sub_with_sponsors_customer.customer
        assert_predicate customer, :sponsors_purpose?, "expected sponsors-purpose customer"

        refute_predicate sponsors_plan_sub_with_sponsors_customer, :general_purpose_customer?
      end

      test "false when customer does not exist" do
        general_plan_sub = create(:billing_plan_subscription)
        general_plan_sub.update_columns(customer_id: 0)
        general_plan_sub.reload
        assert_nil general_plan_sub.customer, "expected no customer"

        refute_predicate general_plan_sub, :general_purpose_customer?
      end
    end

    context "#has_valid_payment_method?" do
      test "returns false for user-owned plan subscription when user no longer exist" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)
        user.delete

        refute_predicate plan_subscription.reload, :has_valid_payment_method?
      end

      test "returns false for self-serve enterprise-owned plan subscription when business no longer exist" do
        business = create(:business, :with_self_serve_payment)
        plan_subscription = create(:billing_plan_subscription, user: nil, user_id: nil, customer: business.customer)
        business.delete

        refute_predicate plan_subscription.reload, :has_valid_payment_method?
      end

      test "returns true for general-purpose plan subscription if the user has a payment method" do
        user = create(:credit_card_user)
        plan_subscription = create(:billing_plan_subscription, user: user)

        assert_predicate plan_subscription, :has_valid_payment_method?
      end

      test "returns false for general-purpose plan subscription if the user does not have a payment method" do
        user = create(:user, customer: create(:no_credit_card_customer))
        plan_subscription = create(:billing_plan_subscription, user: user)

        refute_predicate plan_subscription, :has_valid_payment_method?
      end

      test "returns true for sponsors-purpose plan subscription" do
        invoiced_org = create(:invoiced_organization,
          plan: GitHub::Plan.free_with_addons,
        )

        sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced,
          payment_method_user: invoiced_org
        )
        create(:customer_account, :sponsors_invoiced,
          customer: sponsors_customer,
          user: invoiced_org
        )
        sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced,
          user: invoiced_org
        )

        refute_predicate invoiced_org, :has_valid_payment_method?, "general-purpose plan subscription should not have a payment method"

        assert_predicate sponsors_plan_sub, :has_valid_payment_method?
      end

      # https://github.com/github/sponsors/issues/5669
      test "returns true for sponsors-purpose plan subscription for an enterprise with valid payment method" do
        sponsors_plan_sub = create(:billing_plan_subscription, :business_owned_with_valid_contact_for_billing, :zuora_business, purpose: :sponsors)
        assert_predicate sponsors_plan_sub.business, :has_valid_payment_method?,
          "need a business with a valid payment method"

        assert_predicate sponsors_plan_sub, :has_valid_payment_method?
      end
    end

    context "#payment_amount" do
      test "returns the amount for a general-purpose plan subscription" do
        user = create(:user, plan: GitHub::Plan.pro, plan_subscription: create(:billing_plan_subscription))
        plan_sub = user.plan_subscription
        assert_equal GitHub::Plan.pro.cost, plan_sub.payment_amount
      end

      test "returns the sponsorship amount for a sponsors-purpose plan subscription" do
        invoiced_org = create(:invoiced_organization)
        sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced,
          payment_method_user: invoiced_org
        )
        create(:customer_account, :sponsors_invoiced,
          customer: sponsors_customer,
          user: invoiced_org
        )
        sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced,
          user: invoiced_org
        )
        sponsors_sub_item = create(:sponsors_subscription_item,
          plan_subscription: sponsors_plan_sub,
        )

        assert_equal sponsors_sub_item.price.dollars, sponsors_plan_sub.payment_amount
      end
    end

    context "#sponsors_invoiced?" do
      test "returns true for a sponsors-purpose plan subscription for a sponsors-purpose customer" do
        sponsors_invoiced_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced)

        assert_predicate sponsors_invoiced_plan_sub, :sponsors_invoiced?
      end

      test "returns false for a sponsors-purpose plan subscription for a general-purpose customer" do
        sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced)
        sponsors_plan_sub.customer.update_column(:purpose, :general)

        refute_predicate sponsors_plan_sub, :sponsors_invoiced?
      end

      test "returns false for a general-purpose plan subscription" do
        plan_sub = create(:billing_plan_subscription, :zuora)

        refute_predicate plan_sub, :sponsors_invoiced?
      end
    end

    context "on zuora subscription number changed" do
      test "resets the memoized attributes for a Zuora subscription" do
        plan_sub = create(:billing_plan_subscription, :zuora)

        fake_sub = Billing::Zuora::Subscription.new(plan_sub.zuora_subscription_id, raw_subscription: {
          id: plan_sub.zuora_subscription_id,
          subscriptionNumber: plan_sub.zuora_subscription_number,
        })
        Billing::Zuora::Subscription.expects(:find).with(plan_sub.zuora_subscription_number).returns(fake_sub)
        assert plan_sub.zuora_subscription

        Billing::Zuora::Subscription.expects(:find).never
        assert plan_sub.zuora_subscription

        plan_sub.update(zuora_subscription_number: "new_number")

        Billing::Zuora::Subscription.expects(:find).with("new_number").returns(fake_sub)
        assert plan_sub.zuora_subscription
      end
    end

    context "org_ids_by_sub_item_ids" do
      test "maps sub item ids to their org ids for enterprise accounts" do
        sponsors_sub_item = create(:sponsors_subscription_item, :self_serve_business)
        plan_sub = sponsors_sub_item.plan_subscription
        business = plan_sub.billable_entity

        other_member_org = create(:organization, business: business)
        other_member_org_sponsors_sub_item = create(:sponsors_subscription_item, account: other_member_org)

        expected_hash = {
          sponsors_sub_item.id => sponsors_sub_item.organization_id,
          other_member_org_sponsors_sub_item.id => other_member_org_sponsors_sub_item.organization_id
        }

        assert_equal expected_hash, plan_sub.org_id_by_sub_item_id
      end

      test "empty mapping for non-enterprise account" do
        sponsors_sub_item = create(:sponsors_subscription_item)
        plan_sub = sponsors_sub_item.plan_subscription

        assert_equal Hash.new, plan_sub.org_id_by_sub_item_id
      end
    end

    context "#sync_customer_in_billing_platform" do
      # user = create(:user)
      # org = create(:credit_card_org, admin: user)
      # plan_subscription = create(:billing_plan_subscription, user: org)

      test "does not enqueue sync job if customer is not billed via Billing Platform" do
        invoiced_org = create(:invoiced_organization)
        invoiced_org.customer.update!(billed_via_billing_platform: false)

        # Process any enqueued jobs
        perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

        assert_enqueued_jobs(0, only: Billing::UpdateCustomerInBillingPlatformJob) do
          plan_sub = create(:billing_plan_subscription, user: invoiced_org)
        end

        assert_dogstats_increment(0, "plan_subscription.billing_platform_update_customer_called")
      end

      test "does not enqueue sync job if feature flag is not enabled" do
        disable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
        invoiced_org = create(:invoiced_organization)
        invoiced_org.customer.update!(billed_via_billing_platform: true)

        # Process any enqueued jobs
        perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

        assert_enqueued_jobs(0, only: Billing::UpdateCustomerInBillingPlatformJob) do
          plan_sub = create(:billing_plan_subscription, user: invoiced_org)
        end

        assert_dogstats_increment(0, "plan_subscription.billing_platform_update_customer_called")
      end

      test "enqueues sync job on creation of plan" do
        enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
        invoiced_org = create(:invoiced_organization)
        invoiced_org.customer.update!(billed_via_billing_platform: true)

        # Process any enqueued jobs
        perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

        assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
          plan_sub = create(:billing_plan_subscription, user: invoiced_org)

          assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [invoiced_org.customer.reload])
        end

        # Synchronization enqueued
        assert_dogstats_increment(1, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:false"])
      end

      test "enqueues sync job on update of plan" do
        enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
        invoiced_org = create(:invoiced_organization)
        invoiced_org.customer.update!(billed_via_billing_platform: true)
        plan_sub = create(:billing_plan_subscription, user: invoiced_org)

        # Process any enqueued jobs
        perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

        assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
          plan_sub.update(zuora_subscription_id: "123", zuora_subscription_number: "A-123")

          assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [invoiced_org.customer.reload])
        end

        # Synchronization enqueued
        assert_dogstats_increment(2, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:false"])
      end

      test "enqueues sync job on deletion of plan" do
        enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
        invoiced_org = create(:invoiced_organization)
        invoiced_org.customer.update!(billed_via_billing_platform: true)
        plan_sub = create(:billing_plan_subscription, user: invoiced_org)

        # Process any enqueued jobs
        perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

        assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
          plan_sub.destroy

          assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [invoiced_org.customer.reload])
        end

        # Synchronization enqueued
        assert_dogstats_increment(2, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:false"])
      end
    end
  end
end
