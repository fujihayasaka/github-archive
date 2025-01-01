# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::ZuoraSubscriptionParamsTest < GitHub::BillingTestCase
    include DogstatsTestHelpers
    include GitHub::ZuoraTestHelper
    include GitHub::SponsorsZuoraTestHelper

    setup do
      synchronize_github_products_to_zuora
      FakeZuora.mock
    end

    context "#rate_plan" do
      test "returns all non sponsors rate plans for a user with a sponsors customer but a general use subscription" do
        user = create :user, plan: :pro
        general_customer = create(:credit_card_customer, payment_method_user: user)
        create(:customer, :sponsors_invoiced, customer_account_user: user)
        plan_subscription = create :billing_plan_subscription, customer: general_customer, user: user

        user.reload

        assert user.sponsors_customer_account

        listing_plan = create :marketplace_listing_plan, :verified_listing, per_unit: true, unit_name: "Seats"
        listing_plan.sync_to_zuora
        mp_sub_item = create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 4
        mp_charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]
        marketplace_params = {
          productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
          chargeOverrides: [{
            Subscription_Item_Id__c: mp_sub_item.id.to_s,
            productRatePlanChargeId: mp_charge_id,
            quantity: 4,
          }],
        }

        copilot_uuid = create(:billing_product_uuid, :copilot)
        create :billing_subscription_item, subscribable: copilot_uuid, plan_subscription: plan_subscription
        copilot_params = {
          productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
          chargeOverrides: []
        }

        macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)
        macos_12_core_params = {
          productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
          chargeOverrides: []
        }

        sponsors_subscription_item = create :sponsors_subscription_item, account: user
        sponsors_tier = sponsors_subscription_item.subscribable
        sponsors_listing = sponsors_tier.listing
        sponsors_listing.sync_to_zuora
        sponsors_params = sponsors_params(
          user: user.reload,
          listing: sponsors_listing,
          tier: sponsors_tier,
        )

        zuora_params = Billing::PlanSubscription::ZuoraSubscriptionParams.new(plan_subscription: plan_subscription)

        assert_includes zuora_params.rate_plans, copilot_params
        assert_includes zuora_params.rate_plans, macos_12_core_params
        assert_includes zuora_params.rate_plans, marketplace_params
        refute_includes zuora_params.rate_plans, sponsors_params
      end
    end

    context "#create_params" do
      test "generates params for a full sync to the subscriptions API with actions enabled" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seats"
          listing_plan.sync_to_zuora
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user
          Asset::Status.create(owner: user, asset_packs: 3)
          customer = plan_subscription.customer
          mp_sub_item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4
          today = GitHub::Billing.today.to_s
          mp_charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]

          macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: Asset::Status.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: Asset::Status.zuora_charge_ids(cycle: user.plan_duration)[:unit],
                quantity: 3,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
          ]

          # MacOS 12-Core runner
          rate_plans << {
            productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
              chargeOverrides: [],
          }

          # Marketplace
          rate_plans += [{
            productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
            chargeOverrides: [{
              Subscription_Item_Id__c: mp_sub_item.id.to_s,
              productRatePlanChargeId: mp_charge_id,
              quantity: 4,
            }],
          }]
          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: true,
          }

          zuora_create_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], zuora_create_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), zuora_create_params.except(:subscribeToRatePlans)

          # pro plan user does NOT have copilot for business
          refute_includes zuora_create_params[:subscribeToRatePlans], copilot_for_biz_rate_plan
        end
      end

      test "raises MissingZuoraRatePlanChargeIdsError when Sponsors listing does not have Zuora product" do
        sub_item = create(:sponsors_subscription_item)
        plan_sub = sub_item.plan_subscription
        zuora_subscription_params = plan_sub.zuora_params

        assert_raises(Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError) do
          zuora_subscription_params.create_params
        end

        context = Failbot.squash_contexts(Failbot.context)
        assert_equal sub_item.subscribable.sponsors_listing_id, context["gh.sponsors_listing.id"]
        assert_equal plan_sub.id, context["gh.plan_subscription.id"]
        assert_equal "month", context["gh.billing_cycle"]
      end

      test "raises MissingZuoraRatePlanChargeIdsError when Marketplace listing plan does not have Zuora product" do
        sub_item = create(:billing_subscription_item)
        assert_predicate sub_item, :subscribable_Marketplace_ListingPlan?
        plan_sub = sub_item.plan_subscription
        zuora_subscription_params = plan_sub.zuora_params

        assert_raises(Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError) do
          zuora_subscription_params.create_params
        end

        context = Failbot.squash_contexts(Failbot.context)
        assert_equal sub_item.subscribable_id, context["gh.marketplace_listing_plan.id"]
        assert_equal plan_sub.id, context["gh.plan_subscription.id"]
        assert_equal "month", context["gh.plan_duration"]
      end

      test "raises MissingZuoraRatePlanChargeIdsError when plan does not have Zuora product" do
        user = create(:user, :zuora, plan: :pro, plan_duration: User::BillingDependency::YEARLY_PLAN)
        product_uuid = user.plan.product_uuid(User::BillingDependency::YEARLY_PLAN)
        product_uuid&.delete
        plan_sub = create(:billing_plan_subscription, customer: user.customer, user: user)
        zuora_subscription_params = plan_sub.zuora_params

        assert_raises(Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError) do
          zuora_subscription_params.create_params
        end

        context = Failbot.squash_contexts(Failbot.context)
        assert_equal plan_sub.id, context["gh.plan_subscription.id"]
        assert_equal "year", context["gh.plan_duration"]
        assert_equal "pro", context["gh.plan"]
        assert_equal user.id, context["gh.user.id"]
        assert_equal "User", context["gh.billable_entity.type"]
        assert_equal user.id, context["gh.billable_entity.id"]
      end

      test "does not synchronize a subscription item on free trial" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          copilot_uuid = create(:billing_product_uuid, :copilot)

          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user
          customer = plan_subscription.customer

          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1,
            free_trial_ends_on: GitHub::Billing.today + 1.month

          today = GitHub::Billing.today.to_s
          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params
          ]

          # Copilot as a ProductUUID
          copilot_rate_plan = {
            productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
            chargeOverrides: []
          }

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          zuora_create_params = plan_subscription.reload.zuora_params.create_params

          assert_equal create_params.except(:subscribeToRatePlans), zuora_create_params.except(:subscribeToRatePlans)
          assert_same_elements create_params[:subscribeToRatePlans], zuora_create_params[:subscribeToRatePlans]

          refute_includes zuora_create_params[:subscribeToRatePlans], copilot_rate_plan
        end
      end

      test "does not synchronize the github rate plan for a business that is being upgraded from an organization, before payment is attempted" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          business = create :business, :with_self_serve_payment
          customer = business.customer
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: customer
          business.initiate_organization_upgrade
          business.reload
          assert_predicate business, :organization_upgrade_initiated?

          today = GitHub::Billing.today.to_s
          rate_plans = [
            actions_rate_plan(plan: business.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: business.plan),
            shared_storage_rate_plan_charge_for(business),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          zuora_create_params = plan_subscription.reload.zuora_params.create_params

          assert_equal create_params.except(:subscribeToRatePlans), zuora_create_params.except(:subscribeToRatePlans)
          assert_same_elements create_params[:subscribeToRatePlans], zuora_create_params[:subscribeToRatePlans]
        end
      end

      test "does not synchronize the github rate plan for a metered business on activation" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          business = create :business, :metered_ghec, trial_expires_at: 30.days.from_now
          customer = business.customer
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: customer
          business.customer.update!(
            billing_type: Customer::BILLING_TYPE_CARD,
            metered_plan: true,
            azure_subscription_id: "80e769f2-ce0f-11ed-afa1-0242ac120002",
            azure_subscription_name: "My subscription"
          )
          business.reload
          business.convert_trial business.owners.first

          today = GitHub::Billing.today.to_s
          rate_plans = [
            actions_rate_plan(plan: business.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: business.plan),
            shared_storage_rate_plan_charge_for(business),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          zuora_create_params = plan_subscription.reload.zuora_params.create_params

          assert_equal create_params.except(:subscribeToRatePlans), zuora_create_params.except(:subscribeToRatePlans)
          assert_same_elements create_params[:subscribeToRatePlans], zuora_create_params[:subscribeToRatePlans]
        end
      end

      test "generated params include Subscription_Item_Id__c custom field" do
        listing_plan = create :marketplace_listing_plan, :verified_listing,
          per_unit: true,
          unit_name: "Seats"
        listing_plan.sync_to_zuora
        user = create :user, plan: :pro
        plan_subscription = create :billing_plan_subscription,
          customer: create(:credit_card_customer),
          user: user
        mp_sub_item = create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 4

        mp_charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]
        marketplace_rate_plan = {
          productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
          chargeOverrides: [{
            Subscription_Item_Id__c: mp_sub_item.id.to_s,
            productRatePlanChargeId: mp_charge_id,
            quantity: 4,
          }]
        }

        actual_params = plan_subscription.reload.zuora_params.create_params

        assert_includes actual_params[:subscribeToRatePlans], marketplace_rate_plan
      end

      test "does not synchronize the github rate plan for a business that is being created from a coupon, before redemption has been completed" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          business = create :business, :with_self_serve_payment
          customer = business.customer
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: customer
          business.initiate_creation_from_coupon
          business.reload
          assert_predicate business, :creation_initiated_from_coupon?

          today = GitHub::Billing.today.to_s
          rate_plans = [
            actions_rate_plan(plan: business.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: business.plan),
            shared_storage_rate_plan_charge_for(business),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          zuora_create_params = plan_subscription.reload.zuora_params.create_params

          assert_equal create_params.except(:subscribeToRatePlans), zuora_create_params.except(:subscribeToRatePlans)
          assert_same_elements create_params[:subscribeToRatePlans], zuora_create_params[:subscribeToRatePlans]
        end
      end

      test "generates params for a full sync to the subscriptions API" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do

          copilot_uuid = create(:billing_product_uuid, :copilot)
          advanced_security_uuid = create(:billing_product_uuid, :advanced_security)
          macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)

          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seats"
          listing_plan.sync_to_zuora
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user
          Asset::Status.create(owner: user, asset_packs: 3)
          customer = plan_subscription.customer
          mp_sub_item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4

          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          create :billing_subscription_item,
            subscribable: advanced_security_uuid,
            plan_subscription: plan_subscription,
            quantity: 3

          today = GitHub::Billing.today.to_s
          mp_charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]
          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: Asset::Status.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: Asset::Status.zuora_charge_ids(cycle: user.plan_duration)[:unit],
                quantity: 3,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            {
              # MacOS 12-Core as a ProductUUID
              productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
              chargeOverrides: [],
            }
          ]

          # Copilot as a ProductUUID
          rate_plans << {
            productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
            chargeOverrides: []
          }

          # Advanced Security as a ProductUUID
          rate_plans << {
            productRatePlanId: advanced_security_uuid.zuora_product_rate_plan_id,
            chargeOverrides: [{
              productRatePlanChargeId: advanced_security_uuid.zuora_product_rate_plan_charge_ids[:unit],
              quantity: 3,
            }]
          }

          # Marketplace
          rate_plans << {
            productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
            chargeOverrides: [{
              Subscription_Item_Id__c: mp_sub_item.id.to_s,
              productRatePlanChargeId: mp_charge_id,
              quantity: 4,
            }],
          }

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: true,
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "generates params for a full sync without collect invoice for a manual transaction customer" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seats"
          listing_plan.sync_to_zuora
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:india_based_credit_card_customer),
            user: user
          Asset::Status.create(owner: user, asset_packs: 3)
          customer = plan_subscription.customer
          mp_sub_item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4

          macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)

          today = GitHub::Billing.today.to_s
          mp_charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]
          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: Asset::Status.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: Asset::Status.zuora_charge_ids(cycle: user.plan_duration)[:unit],
                quantity: 3,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            {
              productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
              chargeOverrides: [],
            }
          ]

          # Marketplace
          rate_plans << {
            productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
            chargeOverrides: [{
              Subscription_Item_Id__c: mp_sub_item.id.to_s,
              productRatePlanChargeId: mp_charge_id,
              quantity: 4,
            }],
          }

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "generates params for a full sync without collect invoice for product_uuid subscription items" do
        Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 22)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:india_based_credit_card_customer),
            user: user

          customer = plan_subscription.customer
          copilot_uuid = create(:billing_product_uuid, :copilot)
          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)

          today = GitHub::Billing.today.to_s
          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            {
              productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
              chargeOverrides: []
            },
            {
              productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
              chargeOverrides: []
            }
          ]


          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "sets price to 0 for in-app purchases" do
        user = create(:user, plan: :pro)
        plan_subscription = create(:billing_plan_subscription,
          customer: create(:credit_card_customer),
          user: user
        )

        customer = plan_subscription.customer
        copilot_uuid = create(:billing_product_uuid, :copilot, :monthly)
        create(:billing_subscription_item,
          :iap,
          subscribable: copilot_uuid,
          plan_subscription: plan_subscription,
          quantity: 1
        )

        actual_params = plan_subscription.reload.zuora_params.create_params

        actual_copilot_rate_plan = actual_params[:subscribeToRatePlans].find do |rate_plan|
          rate_plan[:productRatePlanId] == copilot_uuid.zuora_product_rate_plan_id
        end

        # Ensure we have Copilot subscrible rate plan data
        refute_nil actual_copilot_rate_plan

        expected_copilot_rate_plan = {
          productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
          chargeOverrides: [{
            productRatePlanChargeId: copilot_uuid.zuora_product_rate_plan_charge_ids[:flat],
            price: 0
          }]
        }

        assert_equal expected_copilot_rate_plan, actual_copilot_rate_plan
      end

      test "sets full charge overrides for a yearly copilot subscription" do
        Timecop.freeze(GitHub::Billing.timezone.local(2023, 1, 24)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user

          customer = plan_subscription.customer
          copilot_uuid = create(:billing_product_uuid, :copilot, :yearly)
          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          macos_12_core_uuid = create(:billing_product_uuid, :actions_macos_12_core)

          today = GitHub::Billing.today.to_s
          copilot_rate_plan = {
            productRatePlanId: copilot_uuid.zuora_product_rate_plan_id,
            chargeOverrides: [{
              productRatePlanChargeId: copilot_uuid.zuora_product_rate_plan_charge_ids[:flat],
              billCycleType: "ChargeTriggerDay",
              billingPeriodAlignment: "AlignToCharge"
            }]
          }

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            {
              productRatePlanId: macos_12_core_uuid.zuora_product_rate_plan_id,
              chargeOverrides: []
            },
            copilot_rate_plan
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "uses a yearly amount for fixed amount coupons and a user with yearly duration" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create(:user, :zuora, plan: :pro, plan_duration: User::BillingDependency::YEARLY_PLAN)
          plan_subscription = create(:billing_plan_subscription, customer: user.customer, user: user)
          coupon = create(:coupon, discount: 4)
          coupon.sync_to_zuora
          user.redeem_coupon(coupon)
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = stub("zuora_subscription",
            charged_through_date: "2020-04-08",
            payment_amount: Billing::Money.new(user.payment_amount * 100),
            active_rate_plans: rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 6,
                }],
              },
            ]),
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: coupon.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: coupon.zuora_charge_ids(cycle: user.plan_duration)[:fixed_discount],
                discountAmount: 48,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: plan_subscription.customer.zuora_account_id,
            contractEffectiveDate: GitHub::Billing.today.to_s,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "creates a subscription with annual discount if allowed" do
        disable_feature_flag(:remove_org_annual_discount)

        Timecop.freeze(GitHub::Billing.timezone.local(2021, 12, 3)) do
          plan = GitHub::Plan.business
          plan_duration = User::BillingDependency::YEARLY_PLAN
          org = create(
            :organization,
            :zuora,
            plan: plan,
            seats: 6,
            plan_duration: plan_duration,
          )
          plan_subscription = create(:billing_plan_subscription, user: org)
          GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "year").returns(
            base_unit: "123_base_unit",
            unit: "123_unit",
            annual_discount: "123_charge_id"
          )
          rate_plans = [
            {
              productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
              chargeOverrides: [
                {
                  productRatePlanChargeId: "123_unit",
                  quantity: 1,
                },
                {
                  productRatePlanChargeId: "123_charge_id",
                  discountPercentage: 8.3333333,
                },
                {
                  productRatePlanChargeId: "123_base_unit",
                  quantity: 5,
                }
              ],
            },
            actions_rate_plan(plan: org.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: org.plan),
            shared_storage_rate_plan_charge_for(org),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan,
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: plan_subscription.customer.zuora_account_id,
            contractEffectiveDate: GitHub::Billing.today.to_s,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false
          }

          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "creates a new subscription with a fixed discount" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user
          coupon = create(:coupon, discount: 4)
          coupon.sync_to_zuora
          user.redeem_coupon coupon
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = stub("zuora_subscription",
            charged_through_date: "2020-04-08",
            payment_amount: Billing::Money.new(user.payment_amount * 100),
            active_rate_plans: rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 6,
                }],
              },
            ]),
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: coupon.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: coupon.zuora_charge_ids(cycle: user.plan_duration)[:fixed_discount],
                discountAmount: 4,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: plan_subscription.customer.zuora_account_id,
            contractEffectiveDate: GitHub::Billing.today.to_s,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false
          }
          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "adds a percent off discount" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: user
          coupon = create(:coupon, discount: 0.5)
          coupon.sync_to_zuora
          user.redeem_coupon coupon
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = stub("zuora_subscription",
            charged_through_date: "2020-04-08",
            payment_amount: Billing::Money.new(user.payment_amount * 100),
            active_rate_plans: rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 6,
                }],
              },
            ]),
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [],
            },
            {
              productRatePlanId: coupon.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: coupon.zuora_charge_ids(cycle: user.plan_duration)[:percentage_discount],
                discountPercentage: 50,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: plan_subscription.customer.zuora_account_id,
            contractEffectiveDate: GitHub::Billing.today.to_s,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false
          }
          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "generates params for a full sync with a $0 charge override for an apple iap subscription" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 6, 30)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription, :apple_iap,
            customer: create(:no_credit_card_customer),
            user: user
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = stub("zuora_subscription",
            charged_through_date: "2020-07-30",
            payment_amount: Billing::Money.new(user.payment_amount * 100),
            active_rate_plans: rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  unit: 1
                }],
              },
            ]),
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          rate_plans = [
            {
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              chargeOverrides: [{
                productRatePlanChargeId: user.plan.zuora_charge_ids(cycle: user.plan_duration)[:flat],
                price: 0,
              }],
            },
            actions_rate_plan(plan: user.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: user.plan),
            shared_storage_rate_plan_charge_for(user),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: plan_subscription.customer.zuora_account_id,
            contractEffectiveDate: GitHub::Billing.today.to_s,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false
          }
          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      context "GitHub Sponsors rate plans" do
        test "generates params with SponsorsListing based Zuora rate plans and custom Zuora subscribable" do
          Timecop.freeze(GitHub::Billing.timezone.local(2020, 11, 1)) do
            user = create :user, plan: :pro
            subscription_item = create :sponsors_subscription_item,
              account: user

            plan_subscription = subscription_item.plan_subscription
            sponsors_tier = subscription_item.subscribable
            sponsors_listing = sponsors_tier.listing
            sponsors_listing.sync_to_zuora

            expected_params = sponsors_params(
              user: user.reload,
              listing: sponsors_listing,
              tier: sponsors_tier,
            )
            actual_params = plan_subscription.reload.zuora_params.create_params

            assert_same_elements expected_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
            assert_equal expected_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
          end
        end

        test "does not make multiple product_uuids queries for multiple Sponsors listings" do
          user = create :credit_card_user
          sponsor_item1, sponsor_item2 = create_pair(:sponsors_subscription_item, account: user)
          plan_subscription = sponsor_item1.plan_subscription

          sponsors_listing1 = sponsor_item1.subscribable.sponsors_listing
          sponsors_listing2 = sponsor_item2.subscribable.sponsors_listing
          refute_equal sponsors_listing1, sponsors_listing2, "need two different SponsorsListing records"

          # Create product UUIDs and rate plans:
          sponsors_listing1.sync_to_zuora
          sponsors_listing2.sync_to_zuora

          zuora_params = plan_subscription.reload.zuora_params

          # 1. Billing::ProductUUID.metered
          # 2. sponsorable.sponsors_listing

          assert_query_count_per_table({ product_uuids: 2 }) do
            zuora_params.create_params
          end
        end

        test "does not support skipping proration for Sponsors rate plans" do
          Billing::PlanSubscription.any_instance.stubs(:zuora_subscription).returns(true)

          user = Timecop.freeze(GitHub::Billing.timezone.local(2020, 11, 1)) do
            create :credit_card_user, plan: :pro
          end

          refute_predicate user, :can_skip_sponsorship_proration?

          Timecop.freeze(GitHub::Billing.timezone.local(2020, 11, 3)) do
            subscription_item = create :sponsors_subscription_item,
              account: user

            sponsorship = create(:sponsorship,
              sponsor: user,
              sponsorable: subscription_item.subscribable.sponsors_listing.sponsorable,
              tier: subscription_item.subscribable,
              subscription_item: subscription_item,
              skip_proration: true,
            )

            assert_predicate sponsorship, :skip_proration?

            plan_subscription = subscription_item.plan_subscription
            sponsors_tier = subscription_item.subscribable
            sponsors_listing = sponsors_tier.listing
            sponsors_listing.sync_to_zuora

            expected_params = sponsors_params(
              user: user.reload,
              listing: sponsors_listing,
              tier: sponsors_tier,
            )
            actual_params = plan_subscription.reload.zuora_params.create_params

            assert_same_elements expected_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
            assert_equal expected_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
          end
        end

        test "skips contract effective day for Sponsors rate plans without a Zuora subscription" do
          Billing::PlanSubscription.any_instance.stubs(:zuora_subscription).returns(false)

          user = travel_to(GitHub::Billing.timezone.local(2020, 11, 1)) do
            create :credit_card_user, plan: :pro
          end
          user.customer.update(bill_cycle_day: 1)
          create(:billing_plan_subscription, user: user, zuora_subscription_number: nil)


          travel_to(GitHub::Billing.timezone.local(2020, 11, 3)) do
            subscription_item = create :sponsors_subscription_item,
              account: user

            create(:sponsorship,
              sponsor: user,
              sponsorable: subscription_item.subscribable.sponsors_listing.sponsorable,
              tier: subscription_item.subscribable,
              subscription_item: subscription_item,
              skip_proration: true,
            )

            plan_subscription = subscription_item.plan_subscription
            sponsors_tier = subscription_item.subscribable
            sponsors_listing = sponsors_tier.listing
            sponsors_listing.sync_to_zuora

            expected_params = sponsors_params(
              user: user.reload,
              listing: sponsors_listing,
              tier: sponsors_tier,
            )
            actual_params = plan_subscription.reload.zuora_params.create_params

            assert_same_elements expected_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
            assert_equal expected_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
          end
        end

        # See https://github.com/github/sponsors/issues/5700
        test "does not apply credit balance or collect for Sponsors-invoiced org" do
          org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
          plan_subscription = org.sponsors_plan_subscription
          assert_predicate plan_subscription, :sponsors_purpose?
          assert_predicate plan_subscription.customer, :sponsors_purpose?

          assert plan_subscription.clear_external_subscription_references

          sponsors_listing = create(:sponsors_listing, :approved, :with_uuids)
          create(:sponsorship, sponsor: org, sponsorable: sponsors_listing.sponsorable)

          zuora_subscription_params = plan_subscription.zuora_params
          create_params = zuora_subscription_params.create_params

          assert_equal false, create_params[:applyCreditBalance]
          assert_equal false, create_params[:collect]
          assert_equal true, create_params[:runBilling]
        end

        # See https://github.com/github/sponsors/issues/5700
        test "applies credit balance and collects for non-Sponsors-invoiced org" do
          org = create(:credit_card_org)
          plan_subscription = create(:billing_plan_subscription, :zuora, purpose: :sponsors, user: org)
          assert_predicate plan_subscription, :sponsors_purpose?
          assert_predicate plan_subscription.customer, :general_purpose?

          assert plan_subscription.clear_external_subscription_references

          sponsors_listing = create(:sponsors_listing, :approved, :with_uuids)
          create(:sponsorship, sponsor: org, sponsorable: sponsors_listing.sponsorable)

          zuora_subscription_params = plan_subscription.zuora_params
          create_params = zuora_subscription_params.create_params

          assert_equal true, create_params[:applyCreditBalance]
          assert_equal true, create_params[:collect]
          assert_equal true, create_params[:runBilling]
        end
      end

      context "self-serve payment enterprise account orgs" do
        test "generated params include Subscription_Item_Id__c custom field for two different orgs" do
          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seats"
          listing_plan.sync_to_zuora
          business = create :business, :with_self_serve_payment
          user = business.owners.first
          org1 = create :organization, business: business, admin: user
          org2 = create :organization, business: business, admin: user
          plan_subscription = create :billing_plan_subscription, :business_owned, customer: business.customer

          mp_sub_item1 = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4,
            organization: org1

          mp_sub_item2 = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 2,
            organization: org2

          mp_charge_id = listing_plan.zuora_charge_ids(cycle: business.plan_duration)[:unit]
          marketplace_rate_plans = [{
            productRatePlanId: listing_plan.zuora_id(cycle: business.plan_duration),
            chargeOverrides: [{
              Subscription_Item_Id__c: mp_sub_item1.id.to_s,
              productRatePlanChargeId: mp_charge_id,
              quantity: 4,
            }]
          },
          {
            productRatePlanId: listing_plan.zuora_id(cycle: business.plan_duration),
            chargeOverrides: [{
              Subscription_Item_Id__c: mp_sub_item2.id.to_s,
              productRatePlanChargeId: mp_charge_id,
              quantity: 2,
            }]
          }]
          actual_params = plan_subscription.reload.zuora_params.create_params
          marketplace_rate_plans.each do |mprp|
            assert_includes actual_params[:subscribeToRatePlans], mprp
          end
        end
      end
    end

    context "#update_params" do
      test "does not revert munich updated included minutes for Team plan" do
        Timecop.freeze(MunichPlan::ACTIONS_CHANGE_DATETIME) do
          org = create(
            :organization,
            :zuora,
            plan: GitHub::Plan.business,
            seats: 6,
            billed_on: MunichPlan::ACTIONS_CHANGE_DATE + 5.days
          )
          plan_subscription = create :billing_plan_subscription, :zuora, user: org
          unit_charge_id = GitHub::Plan.business.product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]
          base_charge_id = GitHub::Plan.business.product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:base_unit]

          actions_rate_plan = actions_active_rate_plan
          actions_rate_plan[:ratePlanCharges].first[:includedUnits] = 3000

          calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new
          shared_storage_rate_plan = shared_storage_active_rate_plan
          shared_storage_rate_plan[:ratePlanCharges].first[:includedUnits] = calculator.hourly_rate_for(units_per_month: org.plan.shared_storage_included_megabytes).round

          team_rate_plan = build(
            :zuora_rate_plan,
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [
              attributes_for(
                :zuora_rate_plan_charge,
                productRatePlanChargeId: unit_charge_id,
                quantity: 1,
              ),
              attributes_for(
                :zuora_rate_plan_charge,
                productRatePlanChargeId: base_charge_id,
                quantity: 5,
              ),
            ]
          )
          active_rate_plans = [team_rate_plan] + rate_plan_objects([
            actions_rate_plan,
            custom_actions_active_rate_plan,
            packages_active_rate_plan(plan: org.plan),
            shared_storage_rate_plan,
            codespaces_active_rate_plan,
            copilot_for_biz_active_rate_plan,
          ])

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          assert_empty params[:add], "No addition found for new product."
          assert_empty params[:remove], "No removal found for downgraded product."
          # the important one
          assert_empty params[:update], "No updates expected for Actions minutes change"
        end
      end

      test "doesn't duplicate plans when there is an inactive discount rate plan charge" do
        org = create(:organization, :zuora, plan: GitHub::Plan.business, seats: 6)
        plan_subscription = create :billing_plan_subscription, user: org, zuora_subscription_number: "test"

        charge_ids = GitHub::Plan.business.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids
        github_plan_product_rate_plan_id = org.plan.zuora_id(cycle: org.plan_duration)

        active_rate_plans = [
          attributes_for(
            :zuora_rate_plan,
            productRatePlanId: github_plan_product_rate_plan_id,
            ratePlanCharges: [
              attributes_for(
                :zuora_rate_plan_charge,
                productRatePlanChargeId: charge_ids[:annual_discount].to_s + "huh",
                discountPercentage: 8.3333333,
                effectiveEndDate: 1.month.ago.to_date.to_s,
                effectiveStartDate: 1.year.ago.to_date.to_s,
              ),
              attributes_for(
                :zuora_rate_plan_charge,
                productRatePlanChargeId: charge_ids[:unit],
                quantity: 1,
              ),
              attributes_for(
                :zuora_rate_plan_charge,
                productRatePlanChargeId: charge_ids[:base_unit],
                quantity: 5,
              ),
            ]
          )
        ]

        raw_subscription = attributes_for(:zuora_subscription, ratePlans: active_rate_plans)
        GitHub.zuorest_client.expects(:get_subscription).with("test").returns(raw_subscription)

        params = plan_subscription.reload.zuora_params.update_params

        assert_empty params[:add].select { |p| p[:productRatePlanId] == github_plan_product_rate_plan_id }
        assert_empty params[:remove], "No removals expected."
        assert_empty params[:update], "No updates expected."
      end

      test "has updates when there are changes in any charge overrides" do
        org = create :organization, plan: GitHub::Plan.business.to_s, seats: 4
        plan_subscription = create :billing_plan_subscription, :zuora, user: org
        charge_id = GitHub::Plan.business
          .product_uuid(org.plan_duration)
          .zuora_product_rate_plan_charge_ids[:unit]
        active_rate_plans = rate_plan_objects([
          {
            id: "123rate",
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [
              {
                id: "123chargeid",
                number: "123charge-A",
                productRatePlanChargeId: charge_id,
                quantity: 0,
              },
              {
                id: "123chargeid-2",
                number: "123charge-B",
                productRatePlanChargeId: org.plan.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids[:base_unit],
                quantity: 5,
              }
            ],
          },
        ])

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
        fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
        fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

        params = plan_subscription.reload.zuora_params.update_params

        refute_empty params[:update], "Expected one update but got #{params[:update]}"
        updated_rate_plan = params[:update].detect { |update| update[:ratePlanId] == "123rate" }
        assert_equal "123rate", updated_rate_plan[:ratePlanId]
        charge_updates = updated_rate_plan[:chargeUpdateDetails]
        assert_equal 2, charge_updates.count
        assert_equal 0, charge_updates.detect { |charge_update| charge_update[:ratePlanChargeId] == "123chargeid" }[:quantity]
        assert_equal 4, charge_updates.detect { |charge_update| charge_update[:ratePlanChargeId] == "123chargeid-2" }[:quantity]
      end

      test "does not send annual discount with charge overrides on update" do
        plan_duration = User::BillingDependency::YEARLY_PLAN
        plan = GitHub::Plan.business
        org = create(
          :organization,
          :zuora,
          plan: plan,
          seats: 4,
          plan_duration: plan_duration,
        )
        plan_subscription = create :billing_plan_subscription, :zuora, user: org
        charge_ids = GitHub::Plan.business
          .product_uuid(org.plan_duration)
          .zuora_product_rate_plan_charge_ids

        unit_charge_id = charge_ids[:unit]
        annual_discount_charge_id = charge_ids[:annual_discount]

        active_rate_plans = rate_plan_objects([
          {
            id: "123rate",
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [
              {
                id: "123chargeid",
                number: "123charge-A",
                productRatePlanChargeId: unit_charge_id,
                quantity: 0,
              },
              {
                id: "123chargeid-2",
                number: "123charge-B",
                productRatePlanChargeId: org.plan.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids[:base_unit],
                quantity: 5,
              },
              {
                id: "123-annual-discount-chargeid",
                productRatePlanChargeId: annual_discount_charge_id,
                discountPercentage: 8.3333333,
              }
            ],
          },
        ])

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
        fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
        fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
        params = plan_subscription.reload.zuora_params.update_params

        refute_empty params[:update], "Expected one update but got #{params[:update]}"
        updated_rate_plan = params[:update].detect { |update| update[:ratePlanId] == "123rate" }
        assert_equal "123rate", updated_rate_plan[:ratePlanId]
        charge_updates = updated_rate_plan[:chargeUpdateDetails]
        refute charge_updates.find { |charge_update| charge_update[:ratePlanChargeId] == "123-annual-discount-chargeid" }
        refute charge_updates.find { |charge_update| charge_update.key?(:discountPercentage) }
        assert_equal 2, charge_updates.count
        assert_equal 0, charge_updates.detect { |charge_update| charge_update[:ratePlanChargeId] == "123chargeid" }[:quantity]
        assert_equal 4, charge_updates.detect { |charge_update| charge_update[:ratePlanChargeId] == "123chargeid-2" }[:quantity]
      end

      test "uses separate invoice collection when updating an existing GitHub rate plan charge" do
        org = create :organization, plan: GitHub::Plan.business.to_s, seats: 10
        plan_subscription = create :billing_plan_subscription, :zuora, user: org
        charge_id = GitHub::Plan.business
          .product_uuid(org.plan_duration)
          .zuora_product_rate_plan_charge_ids[:unit]
        active_rate_plans = rate_plan_objects([
          {
            id: "123rate",
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [
              {
                id: "123chargeid",
                number: "123charge",
                productRatePlanChargeId: charge_id,
                quantity: 4,
              },
              {
                id: "123chargeid",
                number: "123charge",
                productRatePlanChargeId: org.plan.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids[:base_unit],
                quantity: 1,
              }
            ],
          },
          actions_active_rate_plan,
          custom_actions_active_rate_plan,
          packages_active_rate_plan(plan: org.plan),
          shared_storage_active_rate_plan,
          codespaces_active_rate_plan,
          copilot_for_biz_active_rate_plan,
        ])

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
        fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
        fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

        org.update!(seats: org.seats + 5)
        params = plan_subscription.reload.zuora_params.update_params

        assert_empty params[:add], "Unexpected addition #{params}"
        assert_empty params[:remove], "Unexpected removal #{params}"
        refute_empty params[:update], "Expected updates #{params}"
        assert params[:runBilling]
      end

      test "uses separate invoice collection when replacing GitHub rate plan charges" do
        org = create :organization, plan: GitHub::Plan.business.to_s, seats: 10
        plan_subscription = create :billing_plan_subscription, :zuora, user: org
        charge_id = GitHub::Plan.business
          .product_uuid(org.plan_duration)
          .zuora_product_rate_plan_charge_ids[:unit]
        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
        fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
        fake_sub.stubs(:active_rate_plans).returns(rate_plan_objects([
          {
            id: "123rate",
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [{
              id: "123chargeid",
              number: "123charge",
              productRatePlanChargeId: charge_id,
              quantity: 5,
            }]
          }
        ]),
                                                  )
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
        org.update!(seats: org.seats + 5, plan: GitHub::Plan.business_plus)

        params = plan_subscription.reload.zuora_params.update_params
        refute_empty params[:add], "Expected addition #{params}"
        refute_empty params[:remove], "Expected removal #{params}"
        assert_empty params[:update], "Unexpected updates #{params}"
        assert params[:runBilling]
      end

      test "collects invoice synchronously with non GitHub rate plan charges" do
        org = create :organization, plan: GitHub::Plan.business.to_s, seats: 10
        plan_subscription = create :billing_plan_subscription, :zuora, user: org
        charge_id = GitHub::Plan.business
          .product_uuid(org.plan_duration)
          .zuora_product_rate_plan_charge_ids[:unit]
        active_rate_plans = rate_plan_objects([
          {
            id: "123rate",
            productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
            ratePlanCharges: [{
              id: "123chargeid",
              number: "123charge",
              productRatePlanChargeId: charge_id,
              quantity: 5,
            }],
          },
          actions_active_rate_plan,
          packages_active_rate_plan(plan: org.plan),
          shared_storage_active_rate_plan,
          codespaces_active_rate_plan,
          copilot_for_biz_active_rate_plan,
        ])

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
        fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
        fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
        org.update!(seats: org.seats + 5, plan: GitHub::Plan.business_plus)

        listing_plan = create :marketplace_listing_plan, :verified_listing,
          per_unit: true,
          unit_name: "Seat"
        create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 4
        listing_plan.sync_to_zuora
        listing_plan.zuora_charge_ids(cycle: org.plan_duration)[:unit]

        params = plan_subscription.reload.zuora_params.update_params
        refute_empty params[:add], "Expected addition #{params}"
        assert_equal 3, params[:add].count
        refute_empty params[:remove], "Expected removal #{params}"
        refute_empty params[:update], "Expected updates #{params}"
        assert params[:runBilling]
        assert_equal true, params[:collect]
      end

      test "handles scheduling a downgrade to the quantity of a marketplace purchase" do
        Timecop.freeze(GitHub::Billing.timezone.local(2021, 2, 9)) do
          user = create(:user)
          plan_subscription = create :billing_plan_subscription, :zuora,
            customer: create(:credit_card_customer),
            user: user
          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seat"
          mp_sub_item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4
          listing_plan.sync_to_zuora
          charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-23"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(listing_plan.monthly_price_in_cents * 7))
          fake_sub.stubs(:active_rate_plans).returns(
            rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  Subscription_Item_Id__c: mp_sub_item.id.to_s,
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 7,
                }],
              },
            ])
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          updated_rate_plan = params[:update].first
          assert_equal GitHub::Billing.today.to_s, updated_rate_plan[:contractEffectiveDate]
          assert_equal "123rate", updated_rate_plan[:ratePlanId]
          charge_updates = updated_rate_plan[:chargeUpdateDetails]
          assert_equal 1, charge_updates.count
          assert_equal 4, charge_updates.first[:quantity]
          assert_equal "123chargeid", charge_updates.first[:ratePlanChargeId]
          assert params[:collect]
          assert params[:runBilling]
        end
      end

      test "contractEffectiveDate is today when scheduling a downgrade to the quantity of a marketplace purchase" do
        Timecop.freeze(GitHub::Billing.timezone.local(2021, 1, 26)) do
          user = create(:user)
          plan_subscription = create :billing_plan_subscription, :zuora,
            customer: create(:credit_card_customer),
            user: user
          listing_plan = create :marketplace_listing_plan, :verified_listing,
            per_unit: true,
            unit_name: "Seat"
          mp_sub_item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4
          listing_plan.sync_to_zuora
          charge_id = listing_plan.zuora_charge_ids(cycle: user.plan_duration)[:unit]

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-23"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(listing_plan.monthly_price_in_cents * 7))
          fake_sub.stubs(:active_rate_plans).returns(rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: listing_plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  Subscription_Item_Id__c: mp_sub_item.id.to_s,
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 7,
                }],
              },
            ])
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          updated_rate_plan = params[:update].first
          assert_equal GitHub::Billing.today.to_s, updated_rate_plan[:contractEffectiveDate]
        end
      end

      test "does not update non quantity based charges if they haven't changed" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          org = create :organization, plan: GitHub::Plan.business, seats: 6
          plan_subscription = create :billing_plan_subscription, :zuora, user: org
          active_rate_plans = rate_plan_objects([
            {
              id: "123rate",
              productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
              ratePlanCharges: [
                {
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: org.plan.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids[:unit],
                  quantity: 1,
                },
                {
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: org.plan.product_uuid(org.plan_duration).zuora_product_rate_plan_charge_ids[:base_unit],
                  quantity: 5,
                }
              ],
            },
          ])

          uuid = ::Billing::PackageRegistry::ZuoraProduct.uuid
          active_rate_plans << Billing::Zuora::RatePlan.new({
            id: "123packageregistryrate",
            productRatePlanId: uuid.zuora_product_rate_plan_id,
            ratePlanCharges: [{
              productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids[:bandwidth],
              includedUnits: org.plan.package_registry_included_bandwidth,
            }],
          })

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          assert_empty params[:update]
        end
      end

      test "applies upgrades to GitHub plans immediately" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          org = create :organization, plan: GitHub::Plan.business, seats: 6
          plan_subscription = create :billing_plan_subscription, :zuora, user: org
          charge_id = GitHub::Plan.business_plus.product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]
          rate_plan_to_remove = build(
              :zuora_rate_plan,
              productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
              ratePlanCharges: [
                attributes_for(
                  :zuora_rate_plan_charge,
                  productRatePlanChargeId: charge_id,
                  quantity: 6
                )
              ]
            )
          active_rate_plans = [rate_plan_to_remove] + rate_plan_objects([
              actions_active_rate_plan,
              custom_actions_active_rate_plan,
              packages_active_rate_plan(plan: org.plan),
              shared_storage_active_rate_plan,
              codespaces_active_rate_plan,
              copilot_for_biz_active_rate_plan,
            ])

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          org.seats = 10
          org.plan = GitHub::Plan.business_plus
          org.save

          params = plan_subscription.reload.zuora_params.update_params
          refute_empty params[:add], "No addition found for new product."
          refute_empty params[:remove], "No removal found for downgraded product."

          assert_equal 1, params[:add].count
          assert_equal 1, params[:remove].count

          business_plus_plan = GitHub::Plan.business_plus
          added_rate_plan_id = business_plus_plan.zuora_id(cycle: org.plan_duration)
          added_charge_id = GitHub::Plan.business_plus.zuora_charge_ids(cycle: org.plan_duration)[:unit]
          expected_additions = [{
            productRatePlanId: added_rate_plan_id,
            contractEffectiveDate: "2020-05-14",
            chargeOverrides: [{
              productRatePlanChargeId: added_charge_id,
              quantity: 10,
            }],
          }]
          expected_additions.each do |expected|
            assert_includes params[:add], expected
          end

          expected_removals = [{
            ratePlanId: rate_plan_to_remove.id,
            contractEffectiveDate: "2020-05-14",
          }]

          expected_removals.each do |removal|
            assert_includes params[:remove], removal
          end
        end
      end

      test "adds discount to upgrade params" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription, :zuora,
            customer: create(:credit_card_customer),
            user: user
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(
            rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 1,
                }],
              },
            ])
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          coupon = create(:coupon, discount: 4)
          coupon.sync_to_zuora
          user.redeem_coupon coupon

          params = plan_subscription.reload.zuora_params.update_params
          refute_empty params[:add], "No addition found for new product."
          assert_empty params[:remove], "No products should be removed."

          added_rate_plan_id = coupon.zuora_id(cycle: user.plan_duration)
          added_charge_id = coupon.zuora_charge_ids(cycle: user.plan_duration)[:fixed_discount]
          addition = params[:add].first
          assert_equal added_rate_plan_id, addition[:productRatePlanId]
          assert_equal "2020-03-27", addition[:contractEffectiveDate]
          charge_overrides = [{
            productRatePlanChargeId: added_charge_id,
            discountAmount: 4.0,
          }]
          assert_equal charge_overrides, addition[:chargeOverrides]
        end
      end

      test "updates discount when user coupon changes" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            :zuora,
            customer: create(:credit_card_customer),
            user: user
          plan_charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]
          coupon = create(:coupon, discount: 0.5)
          coupon.sync_to_zuora
          coupon_charge_id = coupon.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:percentage_discount]
          user.redeem_coupon coupon

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(rate_plan_objects([
            {
              id: "123rate",
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              ratePlanCharges: [{
                id: "123chargeid",
                number: "123charge",
                productRatePlanChargeId: plan_charge_id,
                quantity: 1,
              }],
            },
            {
              id: "123discountRate",
              productRatePlanId: coupon.zuora_id(cycle: user.plan_duration),
              ratePlanCharges: [{
                id: "123chargeid",
                number: "123charge",
                productRatePlanChargeId: coupon_charge_id,
              }],
            },
          ])
                                                    )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          updated_coupon = create(:coupon, discount: 0.7)
          user.expire_active_coupon
          user.redeem_coupon updated_coupon

          params = plan_subscription.reload.zuora_params.update_params
          refute_empty params[:add], "No addition found for new product."
          refute_empty params[:remove], "No removal found for existing product"

          added_rate_plan_id = coupon.zuora_id(cycle: user.plan_duration)
          added_charge_id = coupon.zuora_charge_ids(cycle: user.plan_duration)[:percentage_discount]
          addition = params[:add].detect { |param| param[:productRatePlanId] == added_rate_plan_id }
          assert_equal added_rate_plan_id, addition[:productRatePlanId]
          assert_equal "2020-03-27", addition[:contractEffectiveDate]
          charge_overrides = [{
            productRatePlanChargeId: added_charge_id,
            discountPercentage: 70,
          }]
          assert_equal charge_overrides, addition[:chargeOverrides]

          removal = params[:remove].first
          assert_equal "123discountRate", removal[:ratePlanId]
          assert_equal "2020-03-27", removal[:contractEffectiveDate]
        end
      end

      test "updates discount when user changes between fixed and percentage coupon" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            :zuora,
            customer: create(:credit_card_customer),
            user: user
          plan_charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]
          coupon = create(:coupon, discount: 0.5)
          coupon.sync_to_zuora
          coupon_charge_id = coupon.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:percentage_discount]
          user.redeem_coupon coupon

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(
            rate_plan_objects([
              {
                id: "123rate",
                productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: plan_charge_id,
                  quantity: 1,
                }],
              },
              {
                id: "123discountRate",
                productRatePlanId: coupon.zuora_id(cycle: user.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: coupon_charge_id,
                }],
              },
            ])
          )
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          fixed_coupon = create(:coupon, discount: 4)
          fixed_coupon.sync_to_zuora
          user.expire_active_coupon
          user.redeem_coupon fixed_coupon

          assert_equal "pro", user.reload.plan.name
          params = plan_subscription.reload.zuora_params.update_params
          refute_empty params[:add], "No addition found for new product."
          refute_empty params[:remove], "No removal found for existing product"

          added_rate_plan_id = fixed_coupon.zuora_id(cycle: user.plan_duration)
          added_charge_id = fixed_coupon.zuora_charge_ids(cycle: user.plan_duration)[:fixed_discount]
          addition = params[:add].first
          assert_equal added_rate_plan_id, addition[:productRatePlanId]
          assert_equal "2020-03-27", addition[:contractEffectiveDate]
          charge_overrides = [{
            productRatePlanChargeId: added_charge_id,
            discountAmount: 4.0,
          }]
          assert_equal charge_overrides, addition[:chargeOverrides]

          removal = params[:remove].first
          assert_equal "123discountRate", removal[:ratePlanId]
          assert_equal "2020-03-27", removal[:contractEffectiveDate]
        end
      end

      test "adds $0 price charge overrides for apple iap subscription upgrades" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 6, 30)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription, :zuora, :apple_iap,
            customer: create(:no_credit_card_customer),
            user: user

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-07-30"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          refute_empty params[:add], "No addition found for new product."
          assert_empty params[:remove], "No products should be removed."

          added_rate_plan_id = user.plan.zuora_id(cycle: user.plan_duration)
          added_charge_id = user.plan.zuora_charge_ids(cycle: user.plan_duration)[:flat]
          addition = params[:add].first
          assert_equal added_rate_plan_id, addition[:productRatePlanId]
          assert_equal "2020-06-30", addition[:contractEffectiveDate]
          charge_overrides = [{
            productRatePlanChargeId: added_charge_id,
            price: 0,
          }]
          assert_equal charge_overrides, addition[:chargeOverrides]
        end
      end

      test "removes duplicate rate plans" do
        enable_feature_flag(:billing_remove_duplicate_rate_plans)
        Timecop.freeze(GitHub::Billing.timezone.local(2024, 5, 28)) do
          user = create :credit_card_user, plan: :pro
          plan_subscription = create :billing_plan_subscription, :zuora, user: user

          active_rate_plans = rate_plan_objects([
            { productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration), chargeOverrides: [], id: "1", productName: "pro" },
            { productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration), chargeOverrides: [], id: "2", productName: "pro" },
            actions_rate_plan(plan: user.plan).merge({ id: "3" }),
            custom_actions_rate_plan.merge({ id: "4", productName: "actions" }),
            custom_actions_rate_plan.merge({ id: "5", productName: "actions" }),
            custom_actions_rate_plan.merge({ id: "6", productName: "actions" }),
            packages_rate_plan(plan: user.plan).merge({ id: "7" }),
            shared_storage_rate_plan_charge_for(user).merge({ id: "8" }),
            ::Billing::Codespaces::RatePlan.new.to_zuora_subscription_params.merge({ id: "9" }),
          ])

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2023-06-28"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(active_rate_plans)
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.update_params
          expected_removals = [
            { contractEffectiveDate: "2024-05-28", ratePlanId: "2" },
            { contractEffectiveDate: "2024-05-28", ratePlanId: "5" },
            { contractEffectiveDate: "2024-05-28", ratePlanId: "6" },
          ]
          assert_equal expected_removals, params[:remove]

          assert_dogstats_increment 1, "billing.plan_subscription.duplicate_rate_plan", tags: ["product_name:pro", "count:2"]
          assert_dogstats_increment 1, "billing.plan_subscription.duplicate_rate_plan", tags: ["product_name:actions", "count:3"]
        end
      end

      context "GitHub Sponsors rate plans" do
        test "adds a one-time sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)

          ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:one_time)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
          assert_equal GitHub::Billing.today.to_s,
            product_add[:contractEffectiveDate],

          overrides = product_add[:chargeOverrides]
          refute_empty overrides

          flat_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
          flat_override = overrides.detect do |hash|
            hash[:productRatePlanChargeId] == flat_charge_id
          end
          refute_nil flat_override, "expected a charge override for the flat amount"
          assert_equal tier.to_money,
            flat_override[:price], "expected flat amount to be the same as the chosen tier"

          fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
          fee_override = overrides.detect do |hash|
            hash[:productRatePlanChargeId] == fee_charge_id
          end
          refute_nil fee_override, "expected a charge override for the fee amount"
          assert_equal Billing::Money.zero,
            fee_override[:price], "expected no fee for sponsorship"
        end

        test "adds a one-time sponsorship with fee for credit card org sponsor" do
          org = zuora_org_sponsor
          plan_subscription = sponsors_plan_subscription(org)
          listing = billing_enabled_sponsors_listing
          user = org.admins.first

          tier = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)

          ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: org, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:one_time)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
          assert_equal GitHub::Billing.today.to_s,
            product_add[:contractEffectiveDate],

          overrides = product_add[:chargeOverrides]
          refute_empty overrides

          flat_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
          flat_override = overrides.detect { |hash| hash[:productRatePlanChargeId] == flat_charge_id }
          refute_nil flat_override, "expected a charge override for the flat amount"
          assert_equal tier.to_money, flat_override[:price],
            "expected flat amount to be the same as the chosen tier"

          fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
          fee_override = overrides.detect { |hash| hash[:productRatePlanChargeId] == fee_charge_id }
          refute_nil fee_override, "expected a charge override for the fee amount"
          assert_equal tier.to_money * Sponsorship::PERCENT_SPONSORSHIP_FEE_FOR_CREDIT_CARD_ORGS / 100,
            fee_override[:price], "expected 6% fee for sponsorship"
        end

        test "does not charge fee for non-org users" do
          user = zuora_user_sponsor
          refute_predicate user, :organization?, "need a non-org user"
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)

          ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:one_time)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
          assert_equal GitHub::Billing.today.to_s,
            product_add[:contractEffectiveDate],

          overrides = product_add[:chargeOverrides]
          refute_empty overrides

          flat_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
          flat_override = overrides.detect { |hash| hash[:productRatePlanChargeId] == flat_charge_id }
          refute_nil flat_override, "expected a charge override for the flat amount"
          assert_equal tier.to_money, flat_override[:price],
            "expected flat amount to be the same as the chosen tier"

          fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
          fee_override = overrides.detect { |hash| hash[:productRatePlanChargeId] == fee_charge_id }
          refute_nil fee_override, "expected a charge override for the fee amount"
          assert_equal Billing::Money.zero, fee_override[:price],
            "expected no fee for sponsorship"
        end

        test "adds a recurring sponsorship" do
          monthly_user = zuora_user_sponsor
          monthly_plan_subscription = sponsors_plan_subscription(monthly_user)
          yearly_user = zuora_user_sponsor(plan_duration: :year)
          yearly_plan_subscription = sponsors_plan_subscription(yearly_user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, sponsors_listing: listing)

          [monthly_user, yearly_user].each do |user|
            ::Sponsors::CreateRecurringSponsorship.call(tier: tier, sponsor: user, viewer: user,
              pay_prorated: true,
            )
          end

          [monthly_plan_subscription, yearly_plan_subscription].each do |plan_subscription|
            stub_sponsors_subscription(
              plan_subscription: plan_subscription,
              rate_plans: [],
            )
          end

          [
            [monthly_plan_subscription, tier.to_money, listing.product_uuid(:month)],
            [yearly_plan_subscription, tier.to_money * 12, listing.product_uuid(:year)],
          ].each do |plan_subscription, expected_price, product_uuid|
            refute_nil product_uuid
            product_uuid = T.must(product_uuid)

            zuora_sub_params = plan_subscription.zuora_params

            result = zuora_sub_params.update_params

            assert_empty result[:update]
            assert_empty result[:remove]
            refute_empty result[:add]

            additions = result[:add]

            assert_equal 1, additions.size, "expected Zuora product to be added for a recurring payment"
            product_add = additions.first
            assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
            assert_equal GitHub::Billing.today.to_s, product_add[:contractEffectiveDate]

            overrides = product_add[:chargeOverrides]
            refute_empty overrides

            flat_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
            flat_override = overrides.detect do |hash|
              hash[:productRatePlanChargeId] == flat_charge_id
            end
            refute_nil flat_override, "expected a charge override for the flat amount"
            assert_equal expected_price,
              flat_override[:price], "expected flat amount to be the same as the chosen tier"

            fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
            fee_override = overrides.detect do |hash|
              hash[:productRatePlanChargeId] == fee_charge_id
            end
            refute_nil fee_override, "expected a charge override for the fee amount"
            assert_equal Billing::Money.zero,
              fee_override[:price], "expected no fee for sponsorship"
          end
        end

        test "adds a recurring sponsorship after GA with fee" do
          monthly_org = zuora_org_sponsor
          monthly_plan_subscription = sponsors_plan_subscription(monthly_org)
          yearly_org = zuora_org_sponsor(plan_duration: :year)
          yearly_plan_subscription = sponsors_plan_subscription(yearly_org)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, sponsors_listing: listing)

          travel_to Sponsorship::SPONSORS_PUBLIC_RELEASE_DATE + 1.day do
            [monthly_org, yearly_org].each do |org|
              ::Sponsors::CreateRecurringSponsorship.call(tier: tier, sponsor: org, viewer: org.admins.first,
                pay_prorated: true,
              )
            end
          end

          [monthly_plan_subscription, yearly_plan_subscription].each do |plan_subscription|
            stub_sponsors_subscription(
              plan_subscription: plan_subscription,
              rate_plans: [],
            )
          end

          [
            [monthly_plan_subscription, tier.to_money, listing.product_uuid(:month)],
            [yearly_plan_subscription, tier.to_money * 12, listing.product_uuid(:year)],
          ].each do |plan_subscription, expected_price, product_uuid|
            refute_nil product_uuid
            product_uuid = T.must(product_uuid)

            zuora_sub_params = plan_subscription.zuora_params

            result = zuora_sub_params.update_params

            assert_empty result[:update]
            assert_empty result[:remove]
            refute_empty result[:add]

            additions = result[:add]
            assert_equal 1, additions.size, "expected Zuora product to be added for a recurring payment"
            product_add = additions.first
            assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
            assert_equal GitHub::Billing.today.to_s, product_add[:contractEffectiveDate]

            overrides = product_add[:chargeOverrides]
            refute_empty overrides

            flat_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
            flat_override = overrides.detect do |hash|
              hash[:productRatePlanChargeId] == flat_charge_id
            end
            refute_nil flat_override, "expected a charge override for the flat amount"
            assert_equal expected_price,
              flat_override[:price], "expected flat amount to be the same as the chosen tier"

            fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
            fee_override = overrides.detect do |hash|
              hash[:productRatePlanChargeId] == fee_charge_id
            end
            refute_nil fee_override, "expected a charge override for the fee amount"
            assert_equal expected_price * Sponsorship::PERCENT_SPONSORSHIP_FEE_FOR_CREDIT_CARD_ORGS / 100,
              fee_override[:price], "expected a 6% fee for sponsorship"
          end
        end

        test "adds another one-time sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)

          one_time_date = GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days
          travel_to(one_time_date) do
            sponsorship = ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)
            # fake out the payment process that deactivates the related subscription item
            sponsorship.subscription_item.deactivate_without_callbacks
          end

          ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              one_time_sponsorship_rate_plan(
                tier: tier,
                sponsor: user,
                added_at_date: one_time_date,
              )
            ],
          )

          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:one_time)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
        end

        test "adds a recurring sponsorship after a one-time sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing
          recurring_tier = listing.default_tier
          one_time_tier =
            create(:sponsors_tier, :published, creator: user, sponsors_listing: listing,
              frequency: :one_time)

          monthly_product_uuid = listing.product_uuid(:month)
          refute_nil monthly_product_uuid
          monthly_product_uuid = T.must(monthly_product_uuid)

          one_time_date = GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days
          travel_to(one_time_date) do
            ::Sponsors::AddOneTimePayment.call(tier: one_time_tier, sponsor: user, viewer: user)
          end

          ::Sponsors::CreateRecurringSponsorship.call(tier: recurring_tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              one_time_sponsorship_rate_plan(
                tier: one_time_tier,
                sponsor: user,
                added_at_date: one_time_date,
              )
            ]
          )

          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal monthly_product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
        end

        test "does not remove old one-time sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing
          one_time_tier = create(:sponsors_tier, :published, :one_time,
            creator: user,
            sponsors_listing: listing,
          )

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              one_time_sponsorship_rate_plan(
                tier: one_time_tier,
                sponsor: user,
                added_at_date: GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days
              )
            ]
          )
          zuora_sub_params = plan_subscription.reload.zuora_params

          result = zuora_sub_params.update_params

          additions = result[:add]

          assert_empty result[:update]
          assert_empty result[:remove]
          assert_empty additions
        end

        test "does not add old one-time sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing
          one_time_tier = create(:sponsors_tier, :published, :one_time,
            creator: user,
            sponsors_listing: listing,
          )

          # TODO the sponsorship lock cutoff doesn't control whether these are billable, that's
          # Billing::SubscriptionItem::SponsorsDependency::ONE_TIME_STALE_THRESHOLD and it's only an hour right now?
          one_time_date = GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days
          travel_to(one_time_date) do
            ::Sponsors::AddOneTimePayment.call(tier: one_time_tier, sponsor: user, viewer: user)
          end

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: []
          )
          zuora_sub_params = plan_subscription.reload.zuora_params

          result = zuora_sub_params.update_params

          additions = result[:add]

          assert_empty result[:update]
          assert_empty result[:remove]
          assert_empty additions
        end

        test "does not add a one-time sponsorship when it's already on the Zuora subscription" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, :one_time,
            creator: user,
            sponsors_listing: listing,
          )

          ::Sponsors::AddOneTimePayment.call(tier: tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              one_time_sponsorship_rate_plan(tier: tier, sponsor: user)
            ]
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          additions = result[:add]

          assert_empty result[:update]
          assert_empty result[:remove]
          assert_empty additions
        end

        test "adds a new one-time sponsorship payment when a recurring sponsorship exists" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)
          one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)

          ::Sponsors::CreateRecurringSponsorship.call(tier: recurring_tier, sponsor: user, viewer: user)
          ::Sponsors::AddOneTimePayment.call(tier: one_time_tier, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              recurring_sponsorship_rate_plan(tier: recurring_tier, sponsor: user)
            ],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          one_time_product_uuid = listing.product_uuid(:one_time)
          refute_nil one_time_product_uuid
          one_time_product_uuid = T.must(one_time_product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal one_time_product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
        end

        test "sets the correct contract date for brand new sponsorship when skipping proration" do
          sponsorship_date = GitHub::Billing.timezone.local(2022, 9, 15).to_date
          travel_to sponsorship_date
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing
          customer = T.must(plan_subscription.customer)

          recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)

          # we need _some_ existing bill cycle day to allow skipping proration
          customer.update!(bill_cycle_day: 1)
          user.reload

          ::Sponsors::CreateRecurringSponsorship.call(tier: recurring_tier, sponsor: user, viewer: user,
            pay_prorated: false
          )

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
          )

          # ensure we handle backdating within the current month and to the previous month
          [[10, "2022-09-10"], [20, "2022-08-20"]].each do |bill_cycle_day, expected_date|
            customer.update!(bill_cycle_day: bill_cycle_day)
            user.reload # to pickup new bill cycle day
            zuora_sub_params = plan_subscription.zuora_params

            result = zuora_sub_params.update_params

            assert_empty result[:update]
            assert_empty result[:remove]
            refute_empty result[:add]

            additions = result[:add]

            product_uuid = listing.product_uuid(:month)
            refute_nil product_uuid
            product_uuid = T.must(product_uuid)
            assert_equal 1, additions.size, "expected one sponsorship to be added"
            product_add = additions.first
            assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]

            assert_equal expected_date, product_add[:contractEffectiveDate], "expected contract date to be backdated with a bill cycle day of #{bill_cycle_day}"
          end
        end

        test "supports skipping proration for sponsors-invoiced org" do
          stub_credit_balance(100_000_00) do
            FakeZuora.mock
            sponsorship_date = GitHub::Billing.timezone.local(2022, 9, 15).to_date
            travel_to sponsorship_date
            sponsor = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription,
              admin: create(:user, :verified)
            )
            plan_sub = sponsor.sponsors_plan_subscription
            listing = billing_enabled_sponsors_listing
            customer = T.must(plan_sub.customer)

            recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)

            # we need _some_ existing bill cycle day to allow skipping proration
            customer.update!(bill_cycle_day: 10)
            sponsor.reload

            ::Sponsors::CreateRecurringSponsorship.call(tier: recurring_tier, sponsor: sponsor, viewer: sponsor.admin,
              pay_prorated: false
            )

            stub_sponsors_subscription(
              plan_subscription: plan_sub,
              rate_plans: [],
            )

            zuora_sub_params = plan_sub.zuora_params

            result = zuora_sub_params.update_params

            assert_empty result[:update]
            assert_empty result[:remove]
            refute_empty result[:add]

            additions = result[:add]

            product_uuid = listing.product_uuid(:month)
            refute_nil product_uuid
            product_uuid = T.must(product_uuid)
            assert_equal 1, additions.size, "expected one sponsorship to be added"
            product_add = additions.first
            assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]

            expected_date = "2022-09-10"
            assert_equal expected_date, product_add[:contractEffectiveDate], "expected contract date to be backdated with a bill cycle day of #{expected_date}"
          end
        end

        # see https://github.com/github/sponsors/issues/4723 and https://github.com/github/sponsors/issues/4802
        test "does not set the contract date before the subscription contract effective date when skipping proration and feature enabled" do
          term_start = Date.parse("2020-03-06") # date used to align the subscription
          contract_start = Date.parse("2022-09-01") # date subscription was created
          sponsorship_date = Date.parse("2022-09-15")
          travel_to sponsorship_date
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing
          customer = T.must(plan_subscription.customer)

          recurring_tier = create(:sponsors_tier, :published, sponsors_listing: listing)

          # we need _some_ existing bill cycle day to allow skipping proration
          customer.update!(bill_cycle_day: 1)
          user.reload

          ::Sponsors::CreateRecurringSponsorship.call(tier: recurring_tier, sponsor: user, viewer: user,
            pay_prorated: false
          )

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
            term_start_date: term_start,
            contract_effective_date: contract_start,
          )

          bill_cycle_day = 20
          customer.update!(bill_cycle_day: bill_cycle_day)
          user.reload # to pickup new bill cycle day
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:month)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected one sponsorship to be added"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]

          assert_equal contract_start.to_s, product_add[:contractEffectiveDate], "expected contract date to be partially backdated to the subscription contract effective date"
        end

        test "adds instead of updates multiple one-time sponsorships" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier1 = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)
          tier2 = create(:sponsors_tier, :published, :one_time, creator: user, sponsors_listing: listing)

          one_time_date = GitHub::Billing.today - (Sponsorship::LOCK_CUTOFF_IN_DAYS + 1).days
          travel_to(one_time_date) do
            sponsorship = ::Sponsors::AddOneTimePayment.call(tier: tier1, sponsor: user, viewer: user)
            # fake out the payment process that deactivates the related subscription item
            sponsorship.subscription_item.deactivate_without_callbacks
          end

          ::Sponsors::AddOneTimePayment.call(tier: tier2, sponsor: user, viewer: user)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              one_time_sponsorship_rate_plan(
                tier: tier1,
                sponsor: user,
                added_at_date: one_time_date,
              )
            ],
          )

          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          assert_empty result[:update]
          assert_empty result[:remove]
          refute_empty result[:add]

          additions = result[:add]

          product_uuid = listing.product_uuid(:one_time)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, additions.size, "expected Zuora product to be added for a one-time payment"
          product_add = additions.first
          assert_equal product_uuid.zuora_product_rate_plan_id, product_add[:productRatePlanId]
        end

        test "does not update unchanged recurring sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          tier = create(:sponsors_tier, :published, creator: user, sponsors_listing: listing)

          ::Sponsors::CreateRecurringSponsorship.call(tier: tier, sponsor: user, viewer: user,
            pay_prorated: true,
          )

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              recurring_sponsorship_rate_plan(tier: tier, sponsor: user)
            ],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          additions = result[:add]

          assert_empty result[:update]
          assert_empty result[:remove]
          assert_empty additions
        end

        test "updates changed sponsorship" do
          user = zuora_user_sponsor
          plan_subscription = sponsors_plan_subscription(user)
          listing = billing_enabled_sponsors_listing

          existing_tier = create(:sponsors_tier, :published, creator: user, sponsors_listing: listing)
          new_tier = create(:sponsors_tier, :published, creator: user, sponsors_listing: listing)

          sponsorship = ::Sponsors::CreateRecurringSponsorship.call(tier: existing_tier, sponsor: user, viewer: user,
            pay_prorated: true,
          )
          ::Sponsors::UpdateSponsorshipTier.call(sponsorship, new_tier: new_tier, viewer: user)

          existing_rate_plan = recurring_sponsorship_rate_plan(tier: existing_tier, sponsor: user)
          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              existing_rate_plan
            ],
          )
          zuora_sub_params = plan_subscription.zuora_params

          result = zuora_sub_params.update_params

          additions = result[:add]
          updates = result[:update]

          refute_empty updates
          assert_empty result[:remove]
          assert_empty additions

          product_uuid = listing.product_uuid(:month)
          refute_nil product_uuid
          product_uuid = T.must(product_uuid)
          assert_equal 1, updates.size, "expected Zuora product to be updated for a tier change"
          update = updates.first
          assert_equal GitHub::Billing.today.to_s, update[:contractEffectiveDate]
          assert_equal existing_rate_plan["id"], update[:ratePlanId]

          update_details = update[:chargeUpdateDetails]
          refute_empty update_details

          flat_product_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:flat]
          flat_charge = existing_rate_plan["ratePlanCharges"].find do |charge|
            charge["productRatePlanChargeId"] == flat_product_charge_id
          end
          flat_update = update_details.detect do |hash|
            hash[:ratePlanChargeId] == flat_charge["id"]
          end
          refute_nil flat_update, "expected a charge override for the flat amount"
          assert_equal new_tier.to_money,
            flat_update[:price], "expected flat amount to be the same as the new tier"

          fee_product_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
          fee_charge = existing_rate_plan["ratePlanCharges"].find do |charge|
            charge["productRatePlanChargeId"] == fee_product_charge_id
          end
          fee_update = update_details.detect do |hash|
            hash[:ratePlanChargeId] == fee_charge["id"]
          end
          refute_nil fee_update, "expected a charge override for the fee amount"
          assert_equal Billing::Money.zero,
            fee_update[:price], "expected no fee for sponsorship"
        end

        test "sponsors-purpose plan subscription only adds sponsors products" do
          sponsor = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
          sponsors_plan_subscription = sponsor.sponsors_plan_subscription

          assert sponsor.plan.cost > 0, "sponsor needs a paid GitHub plan (to ensure we don't bill for it)"

          subscription_item = create(:sponsors_subscription_item,
            plan_subscription: sponsors_plan_subscription
          )
          listing = subscription_item.listing
          listing.sync_to_zuora

          stub_sponsors_subscription(
            plan_subscription: sponsors_plan_subscription,
            rate_plans: [],
          )

          params = sponsors_plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_empty update_params
          assert_empty remove_params
          refute_empty add_params, "should have a sponsors product to add"

          expected_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: sponsor.sponsors_plan_duration)

          assert_equal 1, add_params.size, "expected only one sponsors product to add"
          assert_equal expected_rate_plan_id, add_params.first[:productRatePlanId]
        end

        test "does not charge fee for invoiced orgs at sponsorship creation time" do
          sponsor = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
          sponsors_plan_subscription = sponsor.sponsors_plan_subscription

          subscription_item = create(:sponsors_subscription_item,
            plan_subscription: sponsors_plan_subscription
          )
          listing = subscription_item.listing
          listing.sync_to_zuora

          stub_sponsors_subscription(
            plan_subscription: sponsors_plan_subscription,
            rate_plans: [],
          )

          params = sponsors_plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_empty update_params
          assert_empty remove_params
          refute_empty add_params, "should have a sponsors product to add"

          expected_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: sponsor.sponsors_plan_duration)

          assert_equal 1, add_params.size, "expected only one sponsors product to add"
          assert_equal expected_rate_plan_id, add_params.first[:productRatePlanId]

          product_uuid = listing.product_uuid(:month)
          fee_charge_id = product_uuid.zuora_product_rate_plan_charge_ids[:fee]
          overrides = add_params.first[:chargeOverrides]
          fee_override = overrides.detect do |hash|
            hash[:productRatePlanChargeId] == fee_charge_id
          end
          refute_nil fee_override, "expected a charge override for the fee amount"
          assert_equal Billing::Money.zero,
            fee_override[:price], "expected no fee for sponsorship"
        end

        test "sponsors-invoiced org uses a monthly plan duration even if plan duration is yearly" do
          sponsor = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
          sponsors_plan_subscription = sponsor.sponsors_plan_subscription

          assert_predicate sponsor, :yearly_plan?, "org's plan duration should be yearly, but sponsorships will be billed monthly"

          subscription_item = create(:sponsors_subscription_item,
            plan_subscription: sponsors_plan_subscription
          )
          listing = subscription_item.listing
          listing.sync_to_zuora

          stub_sponsors_subscription(
            plan_subscription: sponsors_plan_subscription,
            rate_plans: [],
          )

          params = sponsors_plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_empty update_params
          assert_empty remove_params
          refute_empty add_params, "should have a sponsors product to add"

          expected_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: User::BillingDependency::MONTHLY_PLAN)

          assert_equal 1, add_params.size, "expected only one sponsors product to add"
          assert_equal expected_rate_plan_id, add_params.first[:productRatePlanId]
        end

        test "specifies payment gateway ID when updating a Sponsors-specific subscription when feature enabled" do
          listing = billing_enabled_sponsors_listing
          sub_item = create(:sponsors_subscription_item, subscribable: listing.default_tier)
          plan_subscription = sub_item.plan_subscription
          assert_predicate plan_subscription, :sponsors_purpose?
          # TODO the factory should probably create a plan sub with Zuora details
          plan_subscription.update!(zuora_subscription_number: "test-subscription")

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [],
          )

          zuora_subscription_params = plan_subscription.zuora_params
          update_params = zuora_subscription_params.update_params

          assert_equal GitHub.zuora_sponsors_payment_gateway_id, update_params[:gatewayId]
        end

        test "does not specify payment gateway ID when updating a general-purpose subscription" do
          org = create(:credit_card_org)
          plan_subscription = create(:billing_plan_subscription, :zuora, user: org)
          assert_predicate plan_subscription, :general_purpose?

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-03-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          zuora_subscription_params = plan_subscription.zuora_params
          update_params = zuora_subscription_params.update_params

          refute update_params.key?(:gatewayId)
        end

        # See https://github.com/github/sponsors/issues/5700
        test "does not apply credit balance or collect for Sponsors-invoiced org" do
          org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
          plan_subscription = org.sponsors_plan_subscription
          assert_predicate plan_subscription, :sponsors_purpose?
          assert_predicate plan_subscription.customer, :sponsors_purpose?

          sponsors_listing = create(:sponsors_listing, :approved, :with_uuids)
          create(:sponsorship, sponsor: org, sponsorable: sponsors_listing.sponsorable)

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns("2020-03-08")
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          zuora_subscription_params = plan_subscription.zuora_params
          update_params = zuora_subscription_params.update_params

          assert_equal false, update_params[:applyCreditBalance]
          assert_equal false, update_params[:collect]
          assert_equal true, update_params[:runBilling]
        end

        # See https://github.com/github/sponsors/issues/5700
        test "applies credit balance and collects for non-Sponsors-invoiced org" do
          disable_feature_flag(:sponsors_skip_invoice_collection_for_update)

          org = create(:credit_card_org)
          plan_subscription = create(:billing_plan_subscription, :zuora, purpose: :sponsors, user: org)
          assert_predicate plan_subscription, :sponsors_purpose?
          assert_predicate plan_subscription.customer, :general_purpose?

          sponsors_listing = create(:sponsors_listing, :approved, :with_uuids)
          create(:sponsorship, sponsor: org, sponsorable: sponsors_listing.sponsorable)

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns("2020-03-08")
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(org.payment_amount * 100))
          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          zuora_subscription_params = plan_subscription.zuora_params
          update_params = zuora_subscription_params.update_params

          assert_equal true, update_params[:applyCreditBalance]
          assert_equal true, update_params[:collect]
          assert_equal true, update_params[:runBilling]
        end

        test "does not collect invoice when feature flag enabled" do
          Timecop.freeze(GitHub::Billing.timezone.local(2020, 11, 1)) do
            user = create :user, plan: :pro
            enable_feature_flag(:sponsors_skip_invoice_collection_for_update, user)

            subscription_item = create :sponsors_subscription_item,
              account: user
            sponsors_tier = subscription_item.subscribable
            sponsors_listing = sponsors_tier.listing
            sponsors_listing.sync_to_zuora

            plan_subscription = subscription_item.plan_subscription
            actual_params = plan_subscription.reload.zuora_params.update_params

            assert_equal false, actual_params[:collect]
          end
        end
      end

      context "self-serve payment enterprise account orgs" do
        test "handles scheduling a downgrade to the quantity of a marketplace purchase" do
          Timecop.freeze(GitHub::Billing.timezone.local(2021, 2, 9)) do
            business = create :business, :with_self_serve_payment
            user = business.owners.first
            org = create :organization, business: business, admin: user
            plan_subscription = create :billing_plan_subscription, :business_owned, :zuora, customer: business.customer
            listing_plan = create :marketplace_listing_plan, :verified_listing,
              per_unit: true,
              unit_name: "Seat"
            mp_sub_item = create :billing_subscription_item,
              subscribable: listing_plan,
              plan_subscription: plan_subscription,
              organization: org,
              quantity: 4
            listing_plan.sync_to_zuora
            charge_id = listing_plan.zuora_charge_ids(cycle: business.plan_duration)[:unit]

            fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
              id: plan_subscription.zuora_subscription_id.to_s,
              subscriptionNumber: plan_subscription.zuora_subscription_number,
            })
            fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-23"))
            fake_sub.stubs(:payment_amount).returns(Billing::Money.new(listing_plan.monthly_price_in_cents * 7))
            fake_sub.stubs(:active_rate_plans).returns(
              rate_plan_objects([
                {
                  id: "123rate",
                  productRatePlanId: listing_plan.zuora_id(cycle: business.plan_duration),
                  ratePlanCharges: [{
                    Subscription_Item_Id__c: mp_sub_item.id.to_s,
                    id: "123chargeid",
                    number: "123charge",
                    productRatePlanChargeId: charge_id,
                    quantity: 7,
                  }],
                },
              ])
            )
            Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

            params = plan_subscription.reload.zuora_params.update_params
            updated_rate_plan = params[:update].first
            assert_equal GitHub::Billing.today.to_s, updated_rate_plan[:contractEffectiveDate]
            assert_equal "123rate", updated_rate_plan[:ratePlanId]
            charge_updates = updated_rate_plan[:chargeUpdateDetails]
            assert_equal 1, charge_updates.count
            assert_equal 4, charge_updates.first[:quantity]
            assert_equal "123chargeid", charge_updates.first[:ratePlanChargeId]
            assert params[:collect]
            assert params[:runBilling]
          end
        end

        test "contractEffectiveDate is today when scheduling a downgrade to the quantity of a marketplace purchase" do
          Timecop.freeze(GitHub::Billing.timezone.local(2021, 1, 26)) do
            business = create :business, :with_self_serve_payment,
              customer: create(:customer, :zuora, :self_serve, billing_end_date: 2.weeks.ago)
            user = business.owners.first
            org = create :organization, business: business, admin: user
            plan_subscription = create :billing_plan_subscription, :business_owned, :zuora, customer: business.customer
            listing_plan = create :marketplace_listing_plan, :verified_listing, per_unit: true, unit_name: "Seat"
            mp_sub_item = create :billing_subscription_item,
              subscribable: listing_plan,
              plan_subscription: plan_subscription,
              organization: org,
              quantity: 4
            listing_plan.sync_to_zuora
            charge_id = listing_plan.zuora_charge_ids(cycle: business.plan_duration)[:unit]

            fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
              id: plan_subscription.zuora_subscription_id.to_s,
              subscriptionNumber: plan_subscription.zuora_subscription_number,
            })
            fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-23"))
            fake_sub.stubs(:payment_amount).returns(Billing::Money.new(listing_plan.monthly_price_in_cents * 7))
            fake_sub.stubs(:active_rate_plans).returns(
              rate_plan_objects([
                {
                  id: "123rate",
                  productRatePlanId: listing_plan.zuora_id(cycle: business.plan_duration),
                  ratePlanCharges: [{
                    Subscription_Item_Id__c: mp_sub_item.id.to_s,
                    id: "123chargeid",
                    number: "123charge",
                    productRatePlanChargeId: charge_id,
                    quantity: 7,
                  }],
                },
              ])
            )
            Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

            params = plan_subscription.reload.zuora_params.update_params
            updated_rate_plan = params[:update].first
            assert_equal GitHub::Billing.today.to_s, updated_rate_plan[:contractEffectiveDate]
          end
        end

        test "supports recurring sponsorship addition for multiple member orgs" do
          sub_item = create(:sponsors_subscription_item, :self_serve_business)
          plan_subscription = sub_item.plan_subscription
          business = plan_subscription.billable_entity
          billing_cycle = business.plan_duration
          member_org = sub_item.organization

          other_member_org = create(:organization, business: business)
          other_member_org_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: sub_item.sponsors_tier
          )
          assert_equal other_member_org.business, member_org.business
          assert_equal other_member_org_sub_item.subscribable, sub_item.subscribable

          listing = sub_item.listing
          create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: billing_cycle)

          existing_flat = other_member_org_sub_item.sponsors_tier.price(sponsor: business)
          existing_fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(existing_flat)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              # used to ensure we don't modify other member org's sponsorship using the same tier
              recurring_sponsorship_rate_plan(
                tier: other_member_org_sub_item.subscribable,
                subscription_item: other_member_org_sub_item,
                sponsor: other_member_org,
                fee: existing_fee,
              ),
            ],
          )

          params = plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_equal 1, add_params.size, "expected one added rate plan"
          assert_equal 0, update_params.size, "expected no updated rate plans"
          assert_equal 0, remove_params.size, "expected no removed rate plans"

          assert_equal product_rate_plan_id(sub_item), add_params.first[:productRatePlanId]
          add_charge_overrides = add_params.first[:chargeOverrides]
          assert_equal 2, add_charge_overrides.count
          add_sponsorship_overrides = add_charge_overrides.detect do |overrides|
            overrides[:productRatePlanChargeId] == product_rate_plan_charge_ids(sub_item)[:flat]
          end
          add_fee_overrides = add_charge_overrides.detect do |overrides|
            overrides[:productRatePlanChargeId] == product_rate_plan_charge_ids(sub_item)[:fee]
          end
          refute_nil add_sponsorship_overrides
          refute_nil add_fee_overrides
          add_tier = sub_item.sponsors_tier
          assert_equal add_tier.zuora_tracking_id, add_sponsorship_overrides[:Subscribable_Tracking_Id__c]
          assert_equal add_tier.zuora_tracking_id, add_fee_overrides[:Subscribable_Tracking_Id__c]
          assert_equal sub_item.id.to_s, add_sponsorship_overrides[:Subscription_Item_Id__c]
          assert_equal sub_item.id.to_s, add_fee_overrides[:Subscription_Item_Id__c]
          expected_add_flat_price = add_tier.price(sponsor: business)
          expected_add_fee_price = Sponsorship.fee_for_credit_card_org_sponsorship_at(expected_add_flat_price)
          assert_equal expected_add_flat_price, add_sponsorship_overrides[:price]
          assert_equal expected_add_fee_price, add_fee_overrides[:price]
        end

        test "supports recurring sponsorship update for multiple member orgs" do
          sub_item = create(:sponsors_subscription_item, :self_serve_business, quantity: 0)
          plan_subscription = sub_item.plan_subscription
          business = plan_subscription.billable_entity
          billing_cycle = business.plan_duration
          member_org = sub_item.organization

          other_member_org = create(:organization, business: business)
          other_member_org_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: sub_item.sponsors_tier
          )
          assert_predicate other_member_org_sub_item, :active?
          assert_equal other_member_org.business, member_org.business
          assert_equal other_member_org_sub_item.subscribable, sub_item.subscribable

          listing = sub_item.listing
          updated_tier = create(:sponsors_tier, :published, sponsors_listing: listing)
          updated_sub_item = create(:sponsors_subscription_item, account: member_org, subscribable: updated_tier)

          create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: billing_cycle)

          update_rate_plan_id = "to_update"
          update_flat_rate_plan_charge_id = "#{update_rate_plan_id}_flat_charge"
          update_fee_rate_plan_charge_id = "#{update_rate_plan_id}_fee_charge"

          other_member_org_flat = other_member_org_sub_item.sponsors_tier.price(sponsor: business)
          other_member_org_fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(other_member_org_flat)
          to_update_flat = sub_item.sponsors_tier.price(sponsor: business)
          to_update_fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(to_update_flat)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              # used to ensure we don't update another member org's sponsorship using the same tier
              recurring_sponsorship_rate_plan(
                tier: other_member_org_sub_item.subscribable,
                subscription_item: other_member_org_sub_item,
                sponsor: other_member_org,
                fee: other_member_org_fee
              ),
              # this is the rate plan we intend to update
              recurring_sponsorship_rate_plan(
                tier: sub_item.subscribable,
                subscription_item: sub_item,
                sponsor: member_org,
                rate_plan_id: update_rate_plan_id,
                flat_rate_plan_charge_id: update_flat_rate_plan_charge_id,
                fee_rate_plan_charge_id: update_fee_rate_plan_charge_id,
                fee: to_update_fee,
              ),
            ],
          )

          params = plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_equal 0, add_params.size, "expected no added rate plans"
          assert_equal 1, update_params.size, "expected one updated rate plan"
          assert_equal 0, remove_params.size, "expected no removed rate plans"

          assert_equal update_rate_plan_id, update_params.first[:ratePlanId]
          update_charge_overrides = update_params.first[:chargeUpdateDetails]
          assert_equal 2, update_charge_overrides.count
          update_sponsorship_overrides = update_charge_overrides.detect do |overrides|
            overrides[:ratePlanChargeId] == update_flat_rate_plan_charge_id
          end
          update_fee_overrides = update_charge_overrides.detect do |overrides|
            overrides[:ratePlanChargeId] == update_fee_rate_plan_charge_id
          end
          refute_nil update_sponsorship_overrides
          refute_nil update_fee_overrides
          assert_equal updated_tier.zuora_tracking_id, update_sponsorship_overrides[:Subscribable_Tracking_Id__c]
          assert_equal updated_tier.zuora_tracking_id, update_fee_overrides[:Subscribable_Tracking_Id__c]
          assert_equal updated_sub_item.id.to_s, update_sponsorship_overrides[:Subscription_Item_Id__c]
          assert_equal updated_sub_item.id.to_s, update_fee_overrides[:Subscription_Item_Id__c]
          expected_flat_price = updated_tier.price(sponsor: business)
          expected_fee_price = Sponsorship.fee_for_credit_card_org_sponsorship_at(expected_flat_price)
          assert_equal expected_flat_price, update_sponsorship_overrides[:price]
          assert_equal expected_fee_price, update_fee_overrides[:price]
        end

        test "supports recurring sponsorship removal for multiple member orgs" do
          existing_sub_item = create(:sponsors_subscription_item, :self_serve_business)
          plan_subscription = existing_sub_item.plan_subscription
          business = plan_subscription.billable_entity
          billing_cycle = business.plan_duration
          member_org = existing_sub_item.organization

          sub_item_to_remove = create(:sponsors_subscription_item, account: member_org, quantity: 0)

          other_member_org = create(:organization, business: business)
          other_member_org_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: sub_item_to_remove.sponsors_tier
          )
          assert_predicate other_member_org_sub_item, :active?
          assert_equal other_member_org.business, member_org.business
          assert_equal other_member_org_sub_item.subscribable, sub_item_to_remove.subscribable

          [existing_sub_item, sub_item_to_remove].each do |sub_item|
            listing = sub_item.listing
            create(:billing_product_uuid, :sponsors_listing, listing: listing, billing_cycle: billing_cycle)
          end

          rate_plan_id = "to_remove"
          existing_flat = existing_sub_item.sponsors_tier.price(sponsor: business)
          existing_fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(existing_flat)
          to_remove_flat = sub_item_to_remove.sponsors_tier.price(sponsor: business)
          to_remove_fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(to_remove_flat)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              # this is the rate plan we intend to remove
              recurring_sponsorship_rate_plan(
                tier: sub_item_to_remove.subscribable,
                subscription_item: sub_item_to_remove,
                sponsor: member_org,
                rate_plan_id: rate_plan_id,
                fee: to_remove_fee,
              ),
              # used to ensure we don't accidentally remove other sponsorships from this org
              recurring_sponsorship_rate_plan(
                tier: existing_sub_item.subscribable,
                subscription_item: existing_sub_item,
                sponsor: member_org,
                fee: existing_fee,
              ),
              # used to ensure we don't remove other member org's sponsorship using the same tier
              recurring_sponsorship_rate_plan(
                tier: sub_item_to_remove.subscribable,
                subscription_item: other_member_org_sub_item,
                sponsor: other_member_org,
                fee: to_remove_fee, # uses same tier, so same fee
              )
            ],
          )

          params = plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_equal 0, add_params.size, "expected no added rate plans"
          assert_equal 0, update_params.size, "expected no updated rate plan"
          assert_equal 1, remove_params.size, "expected one removed rate plan"

          assert_equal rate_plan_id, remove_params.first[:ratePlanId]
        end

        test "supports one-time sponsorship addition for multiple member orgs" do
          listing = create(:sponsors_listing, :approved)
          one_time_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: listing)
          one_time_sub_item = create(:sponsors_subscription_item, :self_serve_business, subscribable: one_time_tier)
          plan_subscription = one_time_sub_item.plan_subscription
          business = plan_subscription.billable_entity
          member_org = one_time_sub_item.organization

          other_member_org = create(:organization, business: business)
          other_member_org_one_time_sub_item = create(:sponsors_subscription_item,
            account: other_member_org,
            subscribable: one_time_tier
          )
          assert_equal other_member_org.business, member_org.business
          assert_equal other_member_org_one_time_sub_item.subscribable, other_member_org_one_time_sub_item.subscribable

          create(:billing_product_uuid, :sponsors_listing, listing: one_time_sub_item.listing, billing_cycle: "one_time")

          price = one_time_sub_item.sponsors_tier.price(sponsor: business)
          fee = Sponsorship.fee_for_credit_card_org_sponsorship_at(price)

          stub_sponsors_subscription(
            plan_subscription: plan_subscription,
            rate_plans: [
              # used to ensure that we can still add a one-time sponsorship payment even if another member org
              # created a one-time sponsorship payment using the same tier today.
              one_time_sponsorship_rate_plan(
                tier: other_member_org_one_time_sub_item.subscribable,
                subscription_item: other_member_org_one_time_sub_item,
                sponsor: other_member_org,
                fee: fee,
              ),
              # used to ensure that we can still add a one-time sponsorship payment even if we've added one
              # several days ago (the limit is 1 per day per maintainer).
              one_time_sponsorship_rate_plan(
                tier: one_time_sub_item.subscribable,
                added_at_date: GitHub::Billing.today - 4.days,
                subscription_item: one_time_sub_item,
                sponsor: member_org,
                fee: fee,
              ),
            ],
          )

          params = plan_subscription.reload.zuora_params.update_params

          add_params = params[:add]
          update_params = params[:update]
          remove_params = params[:remove]

          assert_equal 1, add_params.size, "expected one added rate plans"
          assert_equal 0, update_params.size, "expected no updated rate plan"
          assert_equal 0, remove_params.size, "expected one removed rate plan"

        end
      end
    end

    context "#cancel_params" do
      test "schedules a plan cancellation at the end of the existing period" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
          user = create :user, plan: :pro
          plan_subscription = create :billing_plan_subscription,
            :zuora,
            customer: create(:credit_card_customer),
            user: user
          charge_id = GitHub::Plan.pro.product_uuid(user.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
            id: plan_subscription.zuora_subscription_id.to_s,
            subscriptionNumber: plan_subscription.zuora_subscription_number,
          })
          fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
          fake_sub.stubs(:payment_amount).returns(Billing::Money.new(user.payment_amount * 100))
          fake_sub.stubs(:active_rate_plans).returns(
            rate_plan_objects([{
              id: "123rate",
              productRatePlanId: user.plan.zuora_id(cycle: user.plan_duration),
              ratePlanCharges: [{
                id: "123chargeid",
                number: "123charge",
                productRatePlanChargeId: charge_id,
                quantity: 6,
              }]
            }])
          )

          Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

          params = plan_subscription.reload.zuora_params.cancel_params
          assert_equal "2020-04-08", params[:cancellationEffectiveDate]
        end
      end

      context "self-serve payment enterprise account orgs" do
        test "schedules a plan cancellation" do
          Timecop.freeze(GitHub::Billing.timezone.local(2020, 3, 27)) do
            business = create :business, :with_self_serve_payment
            user = business.owners.first
            create :organization, business: business, admin: user
            plan_subscription = create :billing_plan_subscription, :business_owned, :zuora, customer: business.customer
            charge_id = GitHub::Plan.pro.product_uuid(business.plan_duration)
              .zuora_product_rate_plan_charge_ids[:unit]

            fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
              id: plan_subscription.zuora_subscription_id.to_s,
              subscriptionNumber: plan_subscription.zuora_subscription_number,
            })
            fake_sub.stubs(:charged_through_date).returns(Date.parse("2020-04-08"))
            fake_sub.stubs(:payment_amount).returns(Billing::Money.new(business.payment_amount * 100))
            fake_sub.stubs(:active_rate_plans).returns(
              rate_plan_objects([{
                id: "123rate",
                productRatePlanId: business.plan.zuora_id(cycle: business.plan_duration),
                ratePlanCharges: [{
                  id: "123chargeid",
                  number: "123charge",
                  productRatePlanChargeId: charge_id,
                  quantity: 6,
                }],
              }])
            )
            Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

            params = plan_subscription.reload.zuora_params.cancel_params
            assert_equal "2020-04-08", params[:cancellationEffectiveDate]
          end
        end
      end
    end

    context "zuora assumes default minimum of 5 seats on team when actual minimum is 1" do
      test "generates correct zuora params when seats are less than 5" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          org = create(:organization, plan: :business, seats: 1) # team plan
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: org
          customer = plan_subscription.customer

          today = GitHub::Billing.today.to_s

          default_quantity_charge_id = GitHub::Plan.business
            .product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:base_unit]
          extra_quantity_charge_id = GitHub::Plan.business
            .product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          rate_plans = [
            {
              productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
              chargeOverrides: [
                {
                  productRatePlanChargeId: extra_quantity_charge_id,
                  quantity: 0
                },
                {
                  productRatePlanChargeId: default_quantity_charge_id,
                  quantity: 1
                },
              ],
            },
            actions_rate_plan(plan: org.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: org.plan),
            shared_storage_rate_plan_charge_for(org),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan,
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }
          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end

      test "generates correct zuora params when seats are more than 5" do
        Timecop.freeze(GitHub::Billing.timezone.local(2020, 5, 14)) do
          org = create(:organization, plan: :business, seats: 7) # team plan
          plan_subscription = create :billing_plan_subscription,
            customer: create(:credit_card_customer),
            user: org
          customer = plan_subscription.customer

          today = GitHub::Billing.today.to_s

          default_quantity_charge_id = GitHub::Plan.business
            .product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:base_unit]
          extra_quantity_charge_id = GitHub::Plan.business
            .product_uuid(org.plan_duration)
            .zuora_product_rate_plan_charge_ids[:unit]

          rate_plans = [
            {
              productRatePlanId: org.plan.zuora_id(cycle: org.plan_duration),
              chargeOverrides: [
                {
                  productRatePlanChargeId: extra_quantity_charge_id,
                  quantity: 2
                },
                {
                  productRatePlanChargeId: default_quantity_charge_id,
                  quantity: 5
                },
              ],
            },
            actions_rate_plan(plan: org.plan),
            custom_actions_rate_plan,
            packages_rate_plan(plan: org.plan),
            shared_storage_rate_plan_charge_for(org),
            Billing::Codespaces::RatePlan.new.to_zuora_subscription_params,
            copilot_for_biz_rate_plan,
          ]

          create_params = {
            applyCreditBalance: true,
            accountKey: customer.zuora_account_id,
            contractEffectiveDate: today,
            termType: "EVERGREEN",
            subscribeToRatePlans: rate_plans,
            runBilling: true,
            collect: false,
          }
          actual_params = plan_subscription.reload.zuora_params.create_params

          assert_same_elements create_params[:subscribeToRatePlans], actual_params[:subscribeToRatePlans]
          assert_equal create_params.except(:subscribeToRatePlans), actual_params.except(:subscribeToRatePlans)
        end
      end
    end
  end
end
