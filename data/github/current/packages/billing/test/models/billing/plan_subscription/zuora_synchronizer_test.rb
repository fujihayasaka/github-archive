# typed: strict
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::ZuoraSynchronizerTest < GitHub::BillingTestCase
    extend T::Sig
    include DogstatsTestHelpers
    include GitHub::Billing::CurrencyTestHelper
    include GitHub::BrainTree::TestHelper
    include GitHub::SponsorsZuoraTestHelper
    include GitHub::ZuoraTestHelper
    include GitHub::LoggerHelper

    ZUORA_SUCCESS = T.let({ "success" => true }, T::Hash[String, T.untyped])
    ZUORA_FAILURE = T.let({
      "success" => false,
      "reasons" => {
        "code"    => "test",
        "message" => "test"
      }
    }, T::Hash[String, T.untyped])
    ZUORA_VERSION_HEADER = Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER

    sig { returns(T::Hash[String, T.untyped]) }
    def create_subscription_mock_response
      ZUORA_SUCCESS.merge("subscriptionId" => "123", "subscriptionNumber" => "A-S123")
    end

    fixtures do
      @pro_user = T.let(create(:user, plan: :pro), T.nilable(User))
    end

    setup do
      GitHub::Experiment.raise_on_mismatches = false
      setup_currency_exchange
      synchronize_github_products_to_zuora
    end

    sig { params(plan_subscription: Billing::PlanSubscription).void }
    def fake_zuora_subscription(plan_subscription)
      fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id.to_s, raw_subscription: {
        id: plan_subscription.zuora_subscription_id.to_s,
        subscriptionNumber: plan_subscription.zuora_subscription_number,
      })
      fake_sub.stubs(:plan_duration).returns(T.must(plan_subscription.user).plan_duration)

      Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
    end

    context "#create" do
      if GitHub.sponsors_enabled?
        test "subscription creation succeeds for invoiced Zuora customer with sufficient credit balance" do
          with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method") do
            user = create(:user, :verified)
            sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced, payment_method_user: user,
              zuora_account_id: "2c92c0f96e63a4ee016e688d1cd53f7b",
              zuora_account_number: "A0100394109")
            create(:customer_account, :sponsors_invoiced, customer: sponsors_customer, user: user)
            sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: user)

            sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
            sponsors_tier.sponsors_listing.sync_to_zuora
            create(:sponsorship, tier: sponsors_tier, sponsor: user)

            account_response = GitHub.zuorest_client.get_account(sponsors_customer.zuora_account_id)
            assert_operator account_response["CreditBalance"], :>=, sponsors_tier.monthly_price_in_dollars.to_i

            result = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_sub).create

            assert_predicate result, :success?
            assert_nil result.error
          end
        end

        test "subscription creation succeeds for enterprise-linked invoiced Zuora customer with sufficient credit balance" do
          stub_credit_balance do
            with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method_sub_creation") do
              sponsors_invoiced_enterprise_linked_org = create(:enterprise_linked_org, :sponsors_invoiced)
              sponsors_customer = sponsors_invoiced_enterprise_linked_org.sponsors_customer
              # values from VCR cassette
              sponsors_customer.update!(
                zuora_account_id: "2c92c0f96e63a4ee016e688d1cd53f7b",
                zuora_account_number: "A0100394109"
              )

              sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
              sponsors_tier.sponsors_listing.sync_to_zuora
              # this service creates an empty plan subscription since it doesn't yet exist
              Billing::CreateSponsorshipSubscriptionItem.call(
                tier: sponsors_tier,
                sponsor: sponsors_invoiced_enterprise_linked_org,
                viewer: sponsors_invoiced_enterprise_linked_org.admin,
              )
              sponsors_plan_sub = sponsors_invoiced_enterprise_linked_org.reload.sponsors_plan_subscription

              assert_nil sponsors_plan_sub.zuora_subscription_id

              account_response = GitHub.zuorest_client.get_account(sponsors_customer.zuora_account_id)
              assert_operator account_response["CreditBalance"], :>=, sponsors_tier.monthly_price_in_dollars.to_i

              result = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_sub).create

              assert_predicate result, :success?
              refute_nil sponsors_plan_sub.reload.zuora_subscription_id
            end
          end
        end

        test "subscription creation succeeds for Sponsors-specific subscription using Sponsors gateway when feature enabled" do
          with_live_zuora("zuora/create_subscription_on_sponsors_gateway") do
            org = create(:invoiced_organization)
            sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced, payment_method_user: org,
              zuora_account_id: "2c92c0f96e63a4ee016e688d1cd53f7b",
              zuora_account_number: "A0100394109")
            create(:customer_account, :sponsors_invoiced, customer: sponsors_customer, user: org)
            sponsors_plan_sub = create(:billing_plan_subscription, purpose: :sponsors, user: org,
              customer: sponsors_customer)

            create_params = sponsors_plan_sub.zuora_params.create_params

            assert_nil sponsors_plan_sub.zuora_subscription_id
            assert_equal GitHub.zuora_sponsors_payment_gateway_id, create_params[:gatewayId],
              "need a plan subscription that will be created on the Sponsors-specific payment gateway"
            assert_equal true, create_params[:invoiceSeparately],
              "need the sponsors-specific Zuora subscription to be invoiced separately"
            assert_equal Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2, create_params[:PaymentGateway__c],
              "need the sponsors-specific Zuora subscription to use the Sponsors-specific payment gateway"

            # Create a Billing::SubscriptionItem so that there are rate plans and the Zuora API will be hit:
            sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
            sponsors_tier.sponsors_listing.sync_to_zuora
            create(:sponsorship, tier: sponsors_tier, sponsor: org)

            result = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_sub).create

            assert_predicate result, :success?
            refute_nil sponsors_plan_sub.reload.zuora_subscription_id
            subscription_id = result.zuora_result["subscriptionId"]
            assert_predicate subscription_id, :present?
            assert_equal subscription_id, sponsors_plan_sub.zuora_subscription_id

            subscription = Billing::Zuora::Subscription.find(subscription_id)
            assert_predicate subscription, :invoice_separately?
            raw_subscription = subscription.send(:raw_subscription)
            assert_equal Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2, raw_subscription[:PaymentGateway__c]
          end
        end

        test "subscription creation fails for invoiced Zuora customer with insufficient credit balance" do
          with_live_zuora("zuora/sponsors_invoiced_account_zero_balance_no_payment_method") do
            user = create(:user, :verified)
            # See test/fixtures/vcr_cassettes/zuora_subscription/successful_create_account_without_card.yml
            sponsors_customer = create(:no_credit_card_customer, :invoiced, :sponsors_invoiced, payment_method_user: user,
              zuora_account_id: "2c92c0fb72ff6f03017301e43ee53fe2",
              zuora_account_number: "A0101275073")
            create(:customer_account, :sponsors_invoiced, customer: sponsors_customer, user: user)
            sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, user: user)

            sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
            sponsors_tier.sponsors_listing.sync_to_zuora
            create(:sponsorship, tier: sponsors_tier, sponsor: user)

            account_response = GitHub.zuorest_client.get_account(sponsors_customer.zuora_account_id)
            assert_operator account_response["CreditBalance"], :<, sponsors_tier.monthly_price_in_dollars.to_i

            result = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_sub).create

            assert_predicate result, :failed?
            assert_equal "To collect payment, the customer account must have a default payment method.", result.error
          end
        end
      end

      test "doesn't attempt to create a subscription for a trade restricted user" do
        with_live_zuora("zuora_subscription/create_subscription_for_user") do
          zuora_user = create :user, :fully_trade_restricted
          zuora_successful_customer_account_creation(zuora_user)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(zuora_user.reload.plan_subscription).create

          assert result.failed?
          assert_equal result.error, "trade restricted user"
        end
      end

      test "creates a subscription for a user on developer plan" do
        pro_user = T.must(@pro_user)
        zuora_successful_customer_account_creation(pro_user)
        pro_user.reload
        plan_subscription = T.must(pro_user.plan_subscription)


        with_live_zuora("zuora_subscription/create_subscription_for_user") do
          invoice_id = "8ad09b7d8292b85d0182a33f53072eaf" # fetched from VCR tape
          args = [T.must(pro_user.customer).zuora_account_id, invoice_id]
          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
          assert_predicate result, :success?

          assert pro_user.reload.plan_subscription.zuora_subscription_number
          plan_subscription = T.must(pro_user.plan_subscription)
          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal pro_user.plan.zuora_id(cycle: pro_user.plan_duration),
            T.must(zuora_sub.active_rate_plans.first)[:productRatePlanId]
          expected_rate_plan_ids = [
            pro_user.plan.zuora_id(cycle: pro_user.plan_duration),
            ::Billing::PackageRegistry::ZuoraProduct.uuid.zuora_product_rate_plan_id,
            ::Billing::Actions::ZuoraProduct.private_visibility_rate_plan_charge.zuora_id,
            ::Billing::Actions::ZuoraProduct.custom_runners_rate_plan_charge.zuora_id,
            ::Billing::SharedStorage::ZuoraProduct.uuid.zuora_product_rate_plan_id,
            ::Billing::Codespaces::RatePlan.new.zuora_product_rate_plan_id,
          ].flatten
          assert_same_elements expected_rate_plan_ids, zuora_sub.active_rate_plans.map { |rate_plan| rate_plan[:productRatePlanId] }
        end
      end

      test "creates a subscription for an organization on Team plan" do
        cassette = "zuora_subscription/create_subscription_for_org_on_business_plan_munich"
        with_live_zuora(cassette) do
          org = create(:organization, plan: :business, seats: 12)

          zuora_successful_customer_account_creation(org)
          org.reload
          plan_subscription = org.plan_subscription

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert org.plan_subscription.reload.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(org.plan_subscription.zuora_subscription_number)

          expected_rate_plan_ids = [
            org.plan.zuora_id(cycle: org.plan_duration),
            ::Billing::PackageRegistry::ZuoraProduct.uuid.zuora_product_rate_plan_id,
            ::Billing::Actions::ZuoraProduct.private_visibility_rate_plan_charge.zuora_id,
            ::Billing::Actions::ZuoraProduct.custom_runners_rate_plan_charge.zuora_id,
            ::Billing::SharedStorage::ZuoraProduct.uuid.zuora_product_rate_plan_id,
            ::Billing::Codespaces::RatePlan.new.zuora_product_rate_plan_id,
          ].flatten
          assert_same_elements expected_rate_plan_ids, zuora_sub.active_rate_plans.map { |rate_plan| rate_plan[:productRatePlanId] }

          business_rate_plan = T.must(zuora_sub.active_rate_plans.first)
          assert_equal org.plan.zuora_id(cycle: org.plan_duration), business_rate_plan[:productRatePlanId]
          assert_equal 2, business_rate_plan[:ratePlanCharges].count
          assert_equal [5, 7], business_rate_plan[:ratePlanCharges].map { |charge| charge[:quantity] }.sort
        end
      end

      test "creates a subscription for an organization on Business plan" do
        with_live_zuora("zuora_subscription/create_subscription_for_org_on_business_plus_plan") do
          org = create(:organization, plan: :business_plus, seats: 7)

          zuora_successful_customer_account_creation(org)
          org.reload
          plan_subscription = org.plan_subscription

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert org.plan_subscription.reload.zuora_subscription_number

          zuora_sub = Billing::Zuora::Subscription.find!(org.plan_subscription.zuora_subscription_number)
          business_plus_product_rate_plan_id = org.plan.zuora_id(cycle: org.plan_duration)
          rate_plan = zuora_sub.active_rate_plans.detect do |rp|
            rp.product_rate_plan_id == business_plus_product_rate_plan_id
          end
          refute_nil rate_plan

          business_plus_rate_plan = T.must(rate_plan)
          assert_equal 1, business_plus_rate_plan[:ratePlanCharges].count
          assert_equal 7, business_plus_rate_plan[:ratePlanCharges].first[:quantity]
        end
      end

      test "creates a subscription for a user with LFS packs" do
        with_live_zuora("zuora_subscription/create_subscription_for_lfs_packs_user") do
          zuora_user = create(:user)
          Asset::Status.create(owner: zuora_user, asset_packs: 3)

          zuora_successful_customer_account_creation(zuora_user)
          zuora_user.reload
          plan_subscription = zuora_user.plan_subscription

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert zuora_user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(zuora_user.plan_subscription.zuora_subscription_number)
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal Asset::Status.zuora_id(cycle: zuora_user.plan_duration),
            T.must(zuora_sub.active_rate_plans.first)[:productRatePlanId]
        end
      end

      test "creates a subscription for a user with a marketplace plan" do
        with_live_zuora("zuora_subscription/create_subscription_for_mp_plan") do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create :marketplace_listing_plan, :published,
            per_unit: true,
            unit_name: "Seats",
            listing: listing
          listing_plan.sync_to_zuora
          user = create :user, plan: "free_with_addons"

          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription
          create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(user.plan_subscription.zuora_subscription_number)
          assert_equal 1, zuora_sub.active_rate_plans.count
          marketplace_rate_plan = T.must(zuora_sub.active_rate_plans.first)
          assert_equal listing_plan.zuora_id(cycle: user.plan_duration), marketplace_rate_plan[:productRatePlanId]
          assert_equal 1, marketplace_rate_plan[:ratePlanCharges].count
          assert_equal 4, marketplace_rate_plan[:ratePlanCharges].first[:quantity]
        end
      end

      test "creates a subscription for a user with copilot enabled" do
        with_live_zuora("zuora_subscription/create_subscription_for_copilot_product_uuid") do
          copilot_uuid = ::Billing::ProductUUID.find_by(product_type: "github.copilot", product_key: "v0", billing_cycle: "month")
          assert copilot_uuid, "expected Copilot UUID record to exist but didn't"
          copilot_uuid = T.must(copilot_uuid)

          user = create :user, plan: "free_with_addons"

          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription
          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(user.plan_subscription.zuora_subscription_number)
          copilot_rate_plan = zuora_sub.active_rate_plans.detect do |rate_plan|
            rate_plan[:productRatePlanId] == copilot_uuid.zuora_product_rate_plan_id
          end
          assert copilot_rate_plan, "expected copilot rate plan to be present in the user's Zuora subscription"
          copilot_rate_plan = T.must(copilot_rate_plan)
          assert_equal 1, copilot_rate_plan[:ratePlanCharges].count
          assert_equal 1, copilot_rate_plan[:ratePlanCharges].first[:quantity]
        end
      end

      test "creates a sponsors-purpose plan subscription for a business" do
        with_live_zuora("zuora_subscriptions/create_sponsors_subscription_for_business") do
          business = create(:business)
          zuora_successful_customer_account_creation(business)
          business.reload
          plan_sub = create(:billing_plan_subscription, :business_owned,
            customer: business.customer,
            purpose: :sponsors
          )
          create(:organization, business: business)
          sub_item = create(:sponsors_subscription_item, plan_subscription: plan_sub)

          sub_item.listing.sync_to_zuora

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_sub).create

          synced_plan_sub = business.reload.sponsors_plan_subscription
          assert_predicate result, :success?
          assert synced_plan_sub.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(synced_plan_sub.zuora_subscription_number)
          assert_equal 1, zuora_sub.active_rate_plans.count
          expected_product_rate_plan_id = sub_item.listing.zuora_rate_plan_id(billing_cycle: business.plan_duration)
          assert_equal expected_product_rate_plan_id, T.must(zuora_sub.active_rate_plans.first).product_rate_plan_id
        end
      end

      test "charges the full price for a user with a subscription and adding Copilot yearly on a different date" do
        with_live_zuora("zuora/copilot_yearly_full_charge") do
          copilot_uuid = ::Billing::ProductUUID.find_by(
            product_type: "github.copilot",
            product_key: "v0",
            billing_cycle: "year"
          )
          assert copilot_uuid, "expected Copilot UUID record to exist but didn't"
          copilot_uuid = T.must(copilot_uuid)

          user = create :user, plan: "free_with_addons"

          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription

          travel_to(GitHub::Billing.timezone.local(2023, 1, 12)) do
            result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
            assert_predicate result, :success?
          end
          assert user.reload.plan_subscription.zuora_subscription_number

          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          update_result = travel_to(GitHub::Billing.timezone.local(2023, 1, 23)) do
            user.plan_subscription.synchronize
          end

          assert_predicate update_result, :success?

          zuora_sub = Billing::Zuora::Subscription.find!(user.plan_subscription.zuora_subscription_number)
          copilot_rate_plan = zuora_sub.active_rate_plans.detect do |rate_plan|
            rate_plan[:productRatePlanId] == copilot_uuid.zuora_product_rate_plan_id
          end
          assert_equal Date.parse("2023-01-12"), zuora_sub.start_date
          assert copilot_rate_plan, "expected copilot rate plan to be present in the user's Zuora subscription"
          copilot_rate_plan = T.must(copilot_rate_plan)
          assert_equal 1, copilot_rate_plan[:ratePlanCharges].count
          assert_equal 1, copilot_rate_plan[:ratePlanCharges].first[:quantity]

          invoice = Billing::Zuora::Invoice.new(update_result.zuora_result["invoiceId"])
          assert_equal 100, invoice.amount

          invoice_items = invoice.invoice_items
          assert_equal 1, invoice_items.count
          copilot_invoice_item = T.must(invoice_items.first)
          assert_equal "2023-01-23", copilot_invoice_item.service_start_date
          assert_equal "2024-01-22", copilot_invoice_item.service_end_date
          assert_equal 100, copilot_invoice_item.charge_amount.dollars
        end
      end

      test "generates an error response for declined payments" do
        user = create :credit_card_user, plan: GitHub::Plan.pro
        plan_subscription = create :billing_plan_subscription, user: user, customer: user.customer

        GitHub.zuorest_client.expects(:create_subscription).returns(
          { success: false, reasons: [{ message: "Declined" }] }.with_indifferent_access
        )

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        refute_predicate result, :success?
        assert_equal result.error_message, "Declined"
      end

      test "generates generic error response by default" do
        user = create :credit_card_user, plan: GitHub::Plan.pro
        plan_subscription = create :billing_plan_subscription, user: user, customer: user.customer
        create(:billing_subscription_sync_status, external_sync_status: :failed_but_retrying, plan_subscription: plan_subscription, target: user, number_of_retries_remaining: 1)

        GitHub.zuorest_client.expects(:create_subscription).returns(
          { success: false, reasons: [{ message: "Random" }] }.with_indifferent_access
        )

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        refute_predicate result, :success?
        assert_equal result.error_message, "Random"
      end

      test "rolls back marketplace purchases on failure with final retry when account is disabled" do
        user = create :credit_card_user, plan: GitHub::Plan.free_with_addons
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan, :published,
          per_unit: true,
          unit_name: "Seats",
          listing: listing
        listing_plan.sync_to_zuora
        plan_subscription = Billing::PlanSubscription.create \
          customer: user.customer,
          user: user
        create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 4
        plan_subscription.reload
        create(:billing_subscription_sync_status, external_sync_status: :failed_but_retrying, plan_subscription: plan_subscription, target: user, number_of_retries_remaining: 1)

        GitHub.zuorest_client.expects(:create_subscription).returns(
          { success: false, reasons: [{ message: "Random" }] }.with_indifferent_access
        )
        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        refute_predicate result, :success?
        assert_empty plan_subscription.reload.active_subscription_items
      end

      test "creates a subscription for a user with a fixed coupon" do
        pro_user = T.must(@pro_user)
        with_live_zuora("zuora_subscription/create_subscription_for_fixed_coupon_user") do
          coupon = create(:coupon, discount: 3)
          coupon.sync_to_zuora
          pro_user.redeem_coupon(coupon)

          zuora_successful_customer_account_creation(pro_user)
          pro_user.reload
          # We must do this since coupons set the billed_on date to today for some reason. The billed_on date will be moved by payment processed webhook
          pro_user.update!(billed_on: T.must(pro_user.billed_on) + 1.month)
          T.must(pro_user.customer).update!(bill_cycle_day: T.must(pro_user.billed_on).day)
          plan_subscription = T.must(pro_user.plan_subscription)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
          assert_equal 2, zuora_sub.active_rate_plans.count
          assert_equal Billing::Money.new(300), zuora_sub.discount
          assert_equal coupon.zuora_id(cycle: pro_user.plan_duration),
            T.must(zuora_sub.active_rate_plans.last)[:productRatePlanId]
        end
      end

      test "creates a subscription for a user with a percentage coupon" do
        pro_user = T.must(@pro_user)
        with_live_zuora("zuora_subscription/create_subscription_for_percentage_coupon_user") do
          coupon = create(:coupon, discount: 0.5)
          coupon.sync_to_zuora
          pro_user.redeem_coupon(coupon)

          zuora_successful_customer_account_creation(pro_user)
          pro_user.reload
          # We must do this since coupons set the billed_on date to today for some reason. The billed_on date will be moved by payment processed webhook
          pro_user.update!(billed_on: T.must(pro_user.billed_on) + 1.month)
          T.must(pro_user.customer).update!(bill_cycle_day: T.must(pro_user.billed_on).day)
          plan_subscription = T.must(pro_user.plan_subscription)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          assert_predicate result, :success?
          assert plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
          assert_equal 2, zuora_sub.active_rate_plans.count
          assert_equal Billing::Money.new(350), zuora_sub.discount
          assert_equal coupon.zuora_id(cycle: pro_user.plan_duration),
            T.must(zuora_sub.active_rate_plans.last)[:productRatePlanId]
        end
      end

      test "does not create a subscription if no rate plans apply" do
        user = create(:user, plan: "free")
        zuora_successful_customer_account_creation(user)
        user.reload

        plan_subscription = user.plan_subscription
        plan_subscription.stubs(:zuora_params).returns(mock("zuora params", rate_plans: []))

        GitHub.zuorest_client.expects(:create_subscription).never

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        assert_predicate result, :success?
      end

      test "attaches an orphaned subscription if there is a timeout" do
        pro_user = T.must(@pro_user)
        zuora_successful_customer_account_creation(pro_user)
        pro_user.reload

        with_live_zuora("zuora_subscription/create_subscription_timeout") do
          plan_subscription = T.must(pro_user.plan_subscription)
          synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription)

          # preconditions
          assert_nil plan_subscription.zuora_subscription_number

          synchronizer.expects(:create_via_subscriptions_endpoint).raises(::Faraday::TimeoutError)
          # Make sure we aren't updating the plan_subscription via success path
          synchronizer.expects(:update_plan_subscription!).never

          assert_raises ::Faraday::TimeoutError do
            synchronizer.create
          end

          assert plan_subscription.zuora_subscription_number
        end
      end

      test "records sponsorship metrics when creates include sponsorships" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        sponsor = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: sponsor)
        sponsor.stubs(:zuora_account).returns({})
        sponsorship = create(:sponsorship, sponsor: sponsor)
        tier = sponsorship.tier
        create(
          :billing_product_uuid,
          product_type: SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE,
          product_key: tier.id.to_s,
          billing_cycle: sponsor.plan_duration,
        )
        sponsors_rate_plan = {
          productRatePlanId: tier.zuora_id(cycle: sponsor.plan_duration),
          chargeOverrides: []
        }

        params = test_create_params
        params[:subscribeToRatePlans] << sponsors_rate_plan
        stubbed_zuora_params = stub(
          create_params: params,
          github_rate_plans: [],
          rate_plans: [sponsors_rate_plan]
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.stubs(:create_subscription).returns(create_subscription_mock_response)

        result =
          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, false).create
        assert_predicate result, :success?

        assert_equal 1, GitHub.dogstats.increments("sponsors.zuora_subscription_update").length
      end

      test "does not record sponsorship metrics when updates do not include sponsorships" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        non_sponsor = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: non_sponsor)
        non_sponsor.stubs(:zuora_account).returns({})

        github_plan = non_sponsor.plan_subscription.plan
        github_rate_plan = {
          productRatePlanId: github_plan.zuora_id(cycle: non_sponsor.plan_duration),
          chargeOverrides: []
        }
        params = test_create_params
        params[:subscribeToRatePlans] << github_rate_plan
        stubbed_zuora_params = stub(
          create_params: params,
          github_rate_plans: [github_rate_plan],
          rate_plans: [github_rate_plan]
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.stubs(:create_subscription).returns(create_subscription_mock_response)

        result =
          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, false).create

        assert_predicate result, :success?

        assert_empty GitHub.dogstats.increments(
          "sponsors.zuora_subscription_update",
          tags: ["transition_enabled:false"]
        )
      end

      test "rolls back marketplace purchases on payment failure on final retry" do
        user = create(:credit_card_user, plan: GitHub::Plan.free, billed_on: GitHub::Billing.today)
        listing = create(:marketplace_listing, :verified)
        listing_plan = create :marketplace_listing_plan, :published,
          per_unit: true,
          unit_name: "Seats",
          listing: listing
        listing_plan.sync_to_zuora

        plan_subscription = Billing::PlanSubscription.create(customer: user.customer, user: user)
        create :billing_subscription_item,
          subscribable: listing_plan,
          plan_subscription: plan_subscription,
          quantity: 1
        plan_subscription.reload
        create(:billing_subscription_sync_status, external_sync_status: :failed_but_retrying, plan_subscription: plan_subscription, target: user, number_of_retries_remaining: 1)

        GitHub.zuorest_client.expects(:create_subscription).returns(
          { success: false, reasons: [{ message: "Random" }] }.with_indifferent_access
        )

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

        refute_predicate result, :success?
        assert_empty plan_subscription.reload.active_subscription_items
      end

      test "overrides collect parameter when specified" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: user)

        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)

        [true, false].each do |collect|
          GitHub.zuorest_client.expects(:create_subscription).with(
            has_entry(collect: collect),
            Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
          ).returns(create_subscription_mock_response)

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, collect: collect).create
        end
      end

      test "updates user's bill cycle day if there are no rate plans on customer's plan subscriptions" do
        general_plan_sub = create(:billing_plan_subscription)
        user = general_plan_sub.user
        sponsors_plan_sub = create(:billing_plan_subscription, user: user, purpose: :sponsors)

        assert_equal sponsors_plan_sub.customer, general_plan_sub.customer, "subscriptions should share a customer"
        assert_empty general_plan_sub.zuora_rate_plan_charges, "general plan sub should not have rate plans"
        assert_empty sponsors_plan_sub.zuora_rate_plan_charges, "sponsors plan sub should not have rate plans"

        synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(general_plan_sub)

        # mock out creation since we're only interested in the side-effects
        general_plan_sub.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.expects(:create_subscription).returns(create_subscription_mock_response)

        # ensure the bill cycle day is updated
        synchronizer.send(:zuora_object_account).expects(:update!).once.with(
          {
            BcdSettingOption: "ManualSet",
            BillCycleDay: GitHub::Billing.today.day,
          }
        ).returns([ZUORA_SUCCESS])

        synchronizer.create
      end

      test "does not update user's bill cycle if there are existing rate plans on customer's plan subscriptions" do
        sponsors_listing = billing_enabled_sponsors_listing
        general_plan_sub = create(:billing_plan_subscription)
        rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
        general_plan_sub.update!(zuora_rate_plan_charges: {
          rate_plan_charge[:productRatePlanChargeId] => {
            number: rate_plan_charge[:number],
            charged_through_date: Date.parse(rate_plan_charge[:chargedThroughDate]),
          }
        })
        create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: general_plan_sub, payload: rate_plan_charge)

        user = general_plan_sub.user
        sponsors_sub_item = create(:sponsors_subscription_item,
          account: user,
          subscribable: sponsors_listing.default_tier,
        )
        sponsors_plan_sub = sponsors_sub_item.plan_subscription

        assert_equal sponsors_plan_sub.customer, general_plan_sub.customer, "subscriptions should share a customer"
        refute_empty general_plan_sub.zuora_rate_plan_charges, "general plan sub should have rate plans"
        assert_empty sponsors_plan_sub.zuora_rate_plan_charges, "sponsors plan sub should not have rate plans"

        synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_sub)

        # mock out creation since we're only interested in the side-effects
        sponsors_plan_sub.stubs(:update_from_zuora_subscription).returns(true)
        synchronizer.expects(:rate_plans).returns(
          [
            recurring_sponsorship_rate_plan(sponsor: user, tier: sponsors_sub_item.sponsors_tier)
          ]
        )
        GitHub.zuorest_client.expects(:create_subscription).returns(create_subscription_mock_response)

        # ensure the bill cycle day is not updated
        synchronizer.send(:zuora_object_account).expects(:update!).never

        synchronizer.create
      end

      test "aligns separate sponsors subscription" do
        # feature flag enabled to allow creating separate subscriptions
        with_live_zuora("zuora/separate_sponsors_subscription_align_charges") do
          user = create(:credit_card_user, :verified, plan_duration: "year")
          customer = user.customer
          # test-yearly-charge-alignment user in the Zuora sandbox environment
          customer.update!(
            zuora_account_id: "8ad08d2986bb64550186befc32945e75",
            zuora_account_number: "A0102179575",
          )
          # This subscription has a start date of 2020-02-29.
          create(:billing_plan_subscription,
            user: user,
            customer: customer,
            zuora_subscription_number: "A-S00101234"
          )

          sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing, monthly_price_in_cents: 1_00)
          sponsors_tier.sponsors_listing.sync_to_zuora
          sponsorship = create(:sponsorship, tier: sponsors_tier, sponsor: user)
          sponsors_plan_subscription = sponsorship.plan_subscription

          assert_predicate sponsors_plan_subscription, :sponsors_purpose?
          refute_predicate sponsors_plan_subscription, :has_external_subscription?

          synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(sponsors_plan_subscription, false)
          result = synchronizer.create

          assert_predicate result, :success?
          # When re-creating the cassette this amount will depend on the proration that occurs in Zuora.
          # We're expecting that it's billed a prorated $12 between now and Feb. 29th (or the closest billing date)
          # of the next year.
          assert_equal 11.67, result.external_result["paidAmount"]
          assert_predicate sponsors_plan_subscription, :has_external_subscription?
        end
      end

      test "aligns separate general-purpose subscription" do
        # feature flag enabled to allow creating separate subscriptions
        with_live_zuora("zuora/separate_general_purpose_subscription_align_charges") do
          user = create(:credit_card_user, :verified, plan: GitHub::Plan.pro, plan_duration: "year")
          customer = user.customer
          # test-yearly-charge-alignment user in the Zuora sandbox environment
          customer.update!(
            zuora_account_id: "8ad08d2986bb64550186befc32945e75",
            zuora_account_number: "A0102179575",
          )
          # this subscription has a start date of '2020-02-29' (leap day for extra edginess :-)
          create(:billing_plan_subscription, :sponsors_invoiced,
            user: user,
            customer: customer,
            zuora_subscription_number: "A-S00101234",
          )
          plan_subscription = create(:billing_plan_subscription,
            user: user,
            customer: customer,
          )
          refute_predicate plan_subscription, :has_external_subscription?

          synchronizer = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, false, collect: true)
          result = synchronizer.create

          assert_predicate result, :success?
          # When re-creating the cassette this amount will depend on the proration that occurs in Zuora.
          # We're expecting that it's billed a prorated $48 between now and Feb. 29th (or the closest billing date)
          # of the next year.
          assert_equal 46.69, result.external_result["paidAmount"]
          assert_predicate plan_subscription, :has_external_subscription?
        end
      end
    end

    context "#update" do
      context "and billing for GitHub Actions" do
        test "downgrades github plan on update" do
          with_live_zuora("zuora_subscription/billing_github_actions/update_subscription_for_github_downgrade") do
            listing = create(:marketplace_listing, :verified)
            listing_plan = create :marketplace_listing_plan, :published,
              per_unit: true,
              unit_name: "Seats",
              listing: listing
            listing_plan.sync_to_zuora
            pro_user = T.must(@pro_user)
            github_plan_zuora_id = pro_user.plan.zuora_id(cycle: pro_user.plan_duration)

            zuora_successful_customer_account_creation(pro_user)
            pro_user.reload
            plan_subscription = T.must(pro_user.plan_subscription)
            item = create :billing_subscription_item,
              subscribable: listing_plan,
              plan_subscription: plan_subscription,
              quantity: 4

            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)

            listing_plan_zuora_id = listing_plan.zuora_id(cycle: pro_user.plan_duration)
            assert zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == listing_plan_zuora_id }

            item.update quantity: 8
            pro_user.update plan: "free_with_addons"

            result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
            assert_predicate result, :success?

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
            marketplace_rate_plan = zuora_sub.active_rate_plans.detect do |rp|
              rp[:productRatePlanId] == listing_plan_zuora_id
            end
            refute_nil marketplace_rate_plan
            assert_equal 8, T.must(marketplace_rate_plan)[:ratePlanCharges].first[:quantity]
            assert zuora_sub.cancelled_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
          end
        end

        test "updates the subscription when downgrading to free with overages allowed" do
          GitHub.zuorest_client.timeout = 30
          pro_user = T.must(@pro_user)
          with_live_zuora("zuora_subscription/billing_github_actions/update_subscription_with_overages_to_free_plan") do
            zuora_successful_customer_account_creation(pro_user)
            pro_user.reload
            plan_subscription = T.must(pro_user.plan_subscription)
            github_plan_zuora_id = pro_user.plan.zuora_id(cycle: pro_user.plan_duration)

            create(:billing_budget, owner: pro_user)

            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

            pro_user.update(plan: "free", billed_on: GitHub::Billing.today + 1.month)
            T.must(pro_user.customer).update(bill_cycle_day: T.must(pro_user.billed_on).day)
            result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
            assert_predicate result, :success?

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
            assert_predicate zuora_sub.active_rate_plans, :present?
            refute zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
            assert zuora_sub.cancelled_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
            assert_equal "Active", zuora_sub.status
            assert pro_user.reload.plan_subscription.zuora_subscription_number
            assert pro_user.billed_on?
            assert pro_user.has_valid_payment_method?
          end
        end

        test "removes charges when they are no longer billable" do
          with_live_zuora("zuora_subscription/update_subscription_to_free_plan") do
            listing = create(:marketplace_listing, :verified)
            listing_plan = create :marketplace_listing_plan, :published,
              per_unit: true,
              unit_name: "Seats",
              listing: listing
            listing_plan.sync_to_zuora

            pro_user = T.must(@pro_user)
            zuora_successful_customer_account_creation(pro_user)
            pro_user.reload
            plan_subscription = T.must(pro_user.plan_subscription)
            item = create :billing_subscription_item,
              subscribable: listing_plan,
              plan_subscription: plan_subscription,
              quantity: 4

            listing_plan_zuora_id = listing_plan.zuora_id(cycle: pro_user.plan_duration)
            github_plan_zuora_id = pro_user.plan.zuora_id(cycle: pro_user.plan_duration)

            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
            assert zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == listing_plan_zuora_id }
            assert pro_user.has_valid_payment_method?

            item.update(quantity: 0)
            pro_user.update(plan: "free", billed_on: GitHub::Billing.today)
            result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
            assert_predicate result, :success?

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
            # Removed GitHub Plan and Marketplace item
            refute zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == listing_plan_zuora_id }
            refute zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
            assert zuora_sub.cancelled_rate_plans.any? { |rp| rp[:productRatePlanId] == listing_plan_zuora_id }
            assert zuora_sub.cancelled_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
            assert_equal "Active", zuora_sub.status
            assert pro_user.reload.plan_subscription.zuora_subscription_number
            assert pro_user.billed_on?
            assert pro_user.has_valid_payment_method?
          end
        end
      end

      test "downgrades github plan on update" do
        with_live_zuora("zuora_subscription/update_subscription_for_github_downgrade") do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create :marketplace_listing_plan, :published,
            per_unit: true,
            unit_name: "Seats",
            listing: listing
          listing_plan.sync_to_zuora

          pro_user = T.must(@pro_user)
          zuora_successful_customer_account_creation(pro_user)
          pro_user.reload
          plan_subscription = T.must(pro_user.plan_subscription)
          item = create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4

          listing_plan_zuora_id = listing_plan.zuora_id(cycle: pro_user.plan_duration)
          github_plan_zuora_id = pro_user.plan.zuora_id(cycle: pro_user.plan_duration)

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
          assert zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == listing_plan_zuora_id }
          assert zuora_sub.active_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }

          item.update quantity: 8
          pro_user.update plan: "free_with_addons"

          result = plan_subscription.synchronize
          assert_predicate result, :success?

          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)
          marketplace_rate_plan = zuora_sub.active_rate_plans.detect do |rp|
            rp[:productRatePlanId] == listing_plan_zuora_id
          end
          refute_nil marketplace_rate_plan
          assert_equal 8, T.must(marketplace_rate_plan)[:ratePlanCharges].first[:quantity]
          assert zuora_sub.cancelled_rate_plans.any? { |rp| rp[:productRatePlanId] == github_plan_zuora_id }
        end
      end

      test "does not cancel and recreate the subscription when there is no duration change" do
        # This bug was caused by the fact that the zuora subscription was cancelled and recreated even
        # when the duration didn't change.
        # For details see: https://github.com/github/gitcoin/issues/9071
        with_live_zuora("zuora_subscription/not_changing_duration_with_copilot_on_yearly") do
          user = create :user, plan: "free_with_addons", plan_duration: User::BillingDependency::YEARLY_PLAN
          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription

          copilot_uuid = ::Billing::ProductUUID.find_by(
            product_type: "github.copilot",
            product_key: "v0",
            billing_cycle: "year"
          )
          create :billing_subscription_item,
            subscribable: copilot_uuid,
            plan_subscription: plan_subscription,
            quantity: 1

          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 21)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create
          end

          existing_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(existing_subscription_id)
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal User::BillingDependency::MONTHLY_PLAN, zuora_sub.plan_duration
          assert existing_subscription_id

          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 22)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          end

          zuora_sub = Billing::Zuora::Subscription.find!(existing_subscription_id)
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal 0, zuora_sub.cancelled_rate_plans.count
          refute_equal "Cancelled", zuora_sub.status

          new_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          assert new_subscription_id
          assert_equal existing_subscription_id, new_subscription_id
        end
      end

      test "does not recreate subscription when changing plan duration from yearly to monthly" do
        with_live_zuora("zuora_subscription/changing_plan_duration_yearly_to_monthly") do
          user = create :user, plan: "pro", plan_duration: User::BillingDependency::YEARLY_PLAN
          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription

          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 26)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create
          end
          existing_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(existing_subscription_id)

          # We expect 6 rate plans because when we create a new zuora subscription, we add a default number
          # of rate plans:
          #
          # 1. GitHub Plan
          # 2. GitHub Actions - Custom Runners
          # 3. GitHub Actions - Private Runners
          # 4. GitHub Packages
          # 5. GitHub Codespaces
          # 6. GitHub Shared Storage
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal 0, zuora_sub.cancelled_rate_plans.count
          assert_equal "GitHub Developer Plan - year", T.must(zuora_sub.active_github_rate_plan)["ratePlanName"]
          assert_equal User::BillingDependency::YEARLY_PLAN, zuora_sub.plan_duration
          assert existing_subscription_id

          user.update(plan_duration: User::BillingDependency::MONTHLY_PLAN)
          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 26)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
          end

          new_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          assert new_subscription_id
          assert_equal existing_subscription_id, new_subscription_id

          zuora_sub = Billing::Zuora::Subscription.find!(new_subscription_id)
          assert_equal "Active", zuora_sub.status
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal 1, zuora_sub.cancelled_rate_plans.count
          assert_equal "GitHub Developer Plan - month", T.must(zuora_sub.active_github_rate_plan)["ratePlanName"]
          assert_equal User::BillingDependency::MONTHLY_PLAN, zuora_sub.plan_duration

          # Assert account billCycleDay is updated
          zuora_account = GitHub.zuorest_client.query_action(
            queryString: "select BillCycleDay from Account where Id = '#{user.reload.customer.zuora_account_id}'",
          )
          assert_equal 26, zuora_account.dig("records", 0, "BillCycleDay")
        end
      end

      test "does not recreate subscription when changing plan duration from monthly to yearly" do
        with_live_zuora("zuora_subscription/changing_plan_duration_monthly_to_yearly") do
          user = create :user, plan: "pro", plan_duration: User::BillingDependency::MONTHLY_PLAN
          zuora_successful_customer_account_creation(user)
          user.reload
          plan_subscription = user.plan_subscription

          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 26)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create
          end
          existing_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(existing_subscription_id)

          # We expect 6 rate plans because when we create a new zuora subscription, we add a default number
          # of rate plans:
          #
          # 1. GitHub Plan
          # 2. GitHub Actions - Custom Runners
          # 3. GitHub Actions - Private Runners
          # 4. GitHub Packages
          # 5. GitHub Codespaces
          # 6. GitHub Shared Storage
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal 0, zuora_sub.cancelled_rate_plans.count
          zuora_successful_customer_account_creation(user)
          assert_equal "GitHub Developer Plan - month", T.must(zuora_sub.active_github_rate_plan)["ratePlanName"]
          assert_equal User::BillingDependency::MONTHLY_PLAN, zuora_sub.plan_duration
          assert existing_subscription_id

          user.update(plan_duration: User::BillingDependency::YEARLY_PLAN)
          Timecop.freeze(GitHub::Billing.timezone.local(2022, 8, 26)) do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
          end

          new_subscription_id = user.reload.plan_subscription.zuora_subscription_number
          assert new_subscription_id
          assert_equal existing_subscription_id, new_subscription_id

          zuora_sub = Billing::Zuora::Subscription.find!(new_subscription_id)
          assert_equal "Active", zuora_sub.status
          assert_equal 6, zuora_sub.active_rate_plans.count
          assert_equal 1, zuora_sub.cancelled_rate_plans.count
          assert_equal "GitHub Developer Plan - year", T.must(zuora_sub.active_github_rate_plan)["ratePlanName"]
          assert_equal User::BillingDependency::YEARLY_PLAN, zuora_sub.plan_duration

          # Assert account billCycleDay is updated
          zuora_account = GitHub.zuorest_client.query_action(
            queryString: "select BillCycleDay from Account where Id = '#{user.reload.customer.zuora_account_id}'",
          )
          assert_equal 26, zuora_account.dig("records", 0, "BillCycleDay")
        end
      end

      test "updates a subscription when changing coupon" do
        with_live_zuora("zuora_subscription/update_subscription_coupon") do
          GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
          coupon = create(:coupon, discount: 0.5)
          coupon.sync_to_zuora
          pro_user = T.must(@pro_user)
          pro_user.redeem_coupon(coupon)

          zuora_successful_customer_account_creation(pro_user)
          pro_user.reload
          # We must do this since coupons set the billed_on date to today for some reason.
          # The billed_on date will be moved by payment processed webhook
          pro_user.update!(billed_on: T.must(pro_user.billed_on) + 1.month)
          T.must(pro_user.customer).update!(bill_cycle_day: T.must(pro_user.billed_on).day)
          plan_subscription = T.must(pro_user.plan_subscription)
          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          updated_coupon = create(:coupon, discount: 0.7)
          pro_user.expire_active_coupon
          pro_user.redeem_coupon updated_coupon
          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update

          assert_predicate result, :success?
          assert plan_subscription.zuora_subscription_number
          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
          expected_discount_amount = pro_user.plan.cost * updated_coupon.discount * 100
          assert_equal Billing::Money.new(expected_discount_amount), zuora_sub.discount
          assert zuora_sub.active_rate_plans.detect { |rp| rp[:productRatePlanId] == updated_coupon.zuora_id(cycle: pro_user.plan_duration) }
          assert_equal 1, GitHub.dogstats.timings("zuora.zuorest.update_subscription.timing").length
        end
      end

      test "updates the account balance from Zuora" do
        with_live_zuora("zuora_subscription/update_subscription_with_account_balance") do
          pro_user = T.must(@pro_user)
          zuora_successful_customer_account_creation(pro_user)
          pro_user.reload

          plan_subscription = T.must(pro_user.plan_subscription)
          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update

          assert_predicate result, :success?

          # This number was manually specified in the VCR cassette for ease of testing
          assert_equal 3_14, plan_subscription.reload.balance_in_cents
        end
      end

      test "resets marketplace purchases when update is declined" do
        user = create :credit_card_user, plan: "free_with_addons"
        plan_subscription = create :billing_plan_subscription,
          customer: user.customer,
          zuora_subscription_number: "A-123456",
          zuora_subscription_id: "123fshjdh423j2hdjdhs34",
          user: user
        fake_zuora_subscription(plan_subscription)

        GitHub.zuorest_client
          .expects(:update_subscription)
          .with(plan_subscription.zuora_subscription_number, anything, Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)
          .returns(:success => false, "reasons" => ["message" => "Declined"])

        Billing::Zuora::BillableRollback.expects(:perform)
          .with(plan_subscription, Billing::PlanSubscription::ZuoraSynchronizer::DECLINED_MESSAGE)
        Failbot.expects(:report!).at_least_once

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update

        assert_predicate result, :failed?
      end

      test "does NOT resets marketplace purchases when update fails on first try" do
        user = create :credit_card_user, plan: "free_with_addons"
        plan_subscription = create :billing_plan_subscription,
          customer: user.customer,
          zuora_subscription_number: "A-123456",
          zuora_subscription_id: "123fshjdh423j2hdjdhs34",
          user: user

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id,
        })
        fake_sub.stubs(plan_duration: user.plan_duration)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

        GitHub.zuorest_client.expects(:update_subscription)
          .with(plan_subscription.zuora_subscription_number, anything, Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)
          .returns(:success => false, "reasons" => ["message" => "error message"])

        Billing::Zuora::BillableRollback.expects(:perform)
          .with(plan_subscription, Billing::PlanSubscription::ZuoraSynchronizer::FAILURE_MESSAGE)
          .never

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
        assert_predicate result, :failed?
      end

      test "resets marketplace purchases when update fails on final retry" do
        user = create :credit_card_user, plan: "free_with_addons"
        plan_subscription = create :billing_plan_subscription,
          customer: user.customer,
          zuora_subscription_number: "A-123456",
          zuora_subscription_id: "123fshjdh423j2hdjdhs34",
          user: user
        create(:billing_subscription_sync_status, external_sync_status: :failed_but_retrying, plan_subscription: plan_subscription, target: user, number_of_retries_remaining: 1)

        fake_zuora_subscription(plan_subscription)

        GitHub.zuorest_client
          .expects(:update_subscription)
          .with(plan_subscription.zuora_subscription_number, anything, Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)
          .returns(:success => false, "reasons" => ["message" => "error message"])

        Billing::Zuora::BillableRollback.expects(:perform)
          .with(plan_subscription, Billing::PlanSubscription::ZuoraSynchronizer::FAILURE_MESSAGE)
          .once

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).update
        assert_predicate result, :failed?
      end

      test "downgrade to free does not delete the protected branches" do
        user = create(:user, :zuora, plan: "pro")
        repo = create(:private_repository, owner: user)

        create(:protected_branch, repository: repo, creator: user)
        user.reload

        plan_subscription = create(:billing_plan_subscription, :zuora, customer: user.customer, user: user)
        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(plan_duration: user.plan_duration)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

        GitHub.zuorest_client.expects(:update_subscription)
          .with(plan_subscription.zuora_subscription_number, anything, Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)
          .returns(success: true)

        user.update(plan: "free")
        Billing::PlanSubscription::Synchronizer.update(plan_subscription)

        # does not remove protected branches because project sculk is now enabled to 100% of users
        refute_empty repo.reload.protected_branches
      end

      test "downgrade to free deletes the protected tags" do
        user = create(:user, :zuora, plan: "pro")
        repo = create(:private_repository, owner: user)

        plan_subscription = create(:billing_plan_subscription, :zuora, customer: user.customer, user: user)
        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id.to_s,
          subscriptionNumber: plan_subscription.zuora_subscription_number,
        })
        fake_sub.stubs(plan_duration: user.plan_duration)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)

        GitHub.zuorest_client.expects(:update_subscription)
          .with(plan_subscription.zuora_subscription_number, anything, Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)
          .returns(success: true)

        user.update(plan: "free")
        Billing::PlanSubscription::Synchronizer.update(plan_subscription)

        assert_empty repo.reload.tag_protection_states
      end

      test "when on new plans, downgrade to free removes access to pages" do
        GitHub.flipper[:pages_soft_deletion].disable
        FakeZuora.mock
        user = create :user, :zuora, plan: "pro"
        repo = create(:private_repository, owner: user)

        create(:page, repository: repo)
        user.reload

        assert repo.page
        assert repo.private?

        plan_subscription = Billing::PlanSubscription.create \
          customer: user.customer,
          user: user

        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_subscription).returns(GitHub::Billing::Result.success)
        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_balance)
        user.update(plan: "free")
        Billing::PlanSubscription::Synchronizer.update(plan_subscription)

        refute repo.reload.page
      end

      test "when on new plans, downgrade to free_with_addons removes access to pages" do
        GitHub.flipper[:pages_soft_deletion].disable
        FakeZuora.mock
        user = create(:user, :zuora, plan: "pro")
        repo = create(:private_repository, owner: user)

        create(:page, repository: repo)
        user.reload

        assert repo.page
        assert repo.private?

        plan_subscription = create(:billing_plan_subscription, customer: user.customer, user: user)

        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_subscription).returns(GitHub::Billing::Result.success)
        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_balance)

        user.update(plan: "free_with_addons")
        Billing::PlanSubscription::Synchronizer.update(plan_subscription)

        refute repo.reload.page
      end

      test "downgrade to free_with_addons does not delete the protected branches" do
        FakeZuora.mock
        user = create(:user, :zuora, plan: "pro")
        repo = create(:private_repository, owner: user)

        create(:protected_branch, repository: repo, creator: user)
        user.reload

        plan_subscription = create(:billing_plan_subscription, customer: user.customer, user: user)

        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_subscription).returns(GitHub::Billing::Result.success)
        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.stubs(:update_balance)

        user.update(plan: "free_with_addons")
        Billing::PlanSubscription::Synchronizer.update(plan_subscription)

        # does not remove protected branches because project sculk
        refute_empty repo.reload.protected_branches
      end

      test "updates in batches" do
        Billing::PlanSubscription::ZuoraSynchronizer.stub_const(:ZUORA_UPDATE_LIMIT, 1) do
          sponsor = create(:credit_card_user, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, user: sponsor)
          sponsor.stubs(:zuora_account).returns({})

          test_batched_update_params = test_update_params.merge(runBilling: false)
          test_batched_update_params.except!(:applyCreditBalance, :collect)
          stubbed_zuora_params = stub(
            update_params: test_update_params,
            github_rate_plans: []
          )
          plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
          plan_subscription.stubs(:update_from_zuora_subscription).returns(true)

          zuora_update_order = sequence("zuora_update_order")

          # First batch of 1 is the add, billing doesn't run yet
          add_params = test_batched_update_params.merge(update: [], remove: [])
          GitHub.zuorest_client.expects(:update_subscription).
            once.
            in_sequence(zuora_update_order).
            with(nil, add_params, ZUORA_VERSION_HEADER).
            returns(ZUORA_SUCCESS)

          # Second batch of 1 is the update, billing doesn't run yet
          update_params = test_batched_update_params.merge(add: [], remove: [])
          GitHub.zuorest_client.expects(:update_subscription).
            once.
            in_sequence(zuora_update_order).
            with(nil, update_params, ZUORA_VERSION_HEADER).
            returns(ZUORA_SUCCESS)

          # Third/final batch of 1 is the remove, billing runs because it's the last batch
          remove_params = test_batched_update_params.merge(
            add: [],
            update: [],
            applyCreditBalance: true,
            collect: true,
            runBilling: true
          )
          GitHub.zuorest_client.expects(:update_subscription).
            once.
            in_sequence(zuora_update_order).
            with(nil, remove_params, ZUORA_VERSION_HEADER
          ).returns(ZUORA_SUCCESS)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          assert_predicate result, :success?
          assert_equal 3, result.batch_zuora_results.count
        end
      end

      test "stops processing update batches when a batch fails" do
        Billing::PlanSubscription::ZuoraSynchronizer.stub_const(:ZUORA_UPDATE_LIMIT, 1) do
          sponsor = create(:credit_card_user, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, user: sponsor)
          sponsor.stubs(:zuora_account).returns({})

          test_batched_update_params = test_update_params.merge(runBilling: false)
          test_batched_update_params.except!(:applyCreditBalance, :collect)
          stubbed_zuora_params = stub(
            update_params: test_update_params,
            github_rate_plans: []
          )
          plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
          plan_subscription.stubs(:update_from_zuora_subscription).returns(true)

          zuora_update_order = sequence("zuora_update_order")

          # First batch of 1 is the add
          add_params = test_batched_update_params.merge(update: [], remove: [])
          GitHub.zuorest_client.expects(:update_subscription).
            once.
            in_sequence(zuora_update_order).
            with(nil, add_params, ZUORA_VERSION_HEADER).
            returns(ZUORA_SUCCESS)

          # Second batch of 1 is the update, where we'll simulate a Zuora fail
          update_params = test_batched_update_params.merge(add: [], remove: [])
          GitHub.zuorest_client.expects(:update_subscription).
            once.
            in_sequence(zuora_update_order).
            with(nil, update_params, ZUORA_VERSION_HEADER).
            returns(ZUORA_FAILURE)

          # Third/final batch of 1 is the remove, which should never happen because the
          # previous batch failed.
          remove_params = test_update_params.merge(
            add: [],
            update: [],
            applyCreditBalance: true,
            collect: true,
            runBilling: true
          )
          GitHub.zuorest_client.expects(:update_subscription).
            never.
            with(nil, remove_params, ZUORA_VERSION_HEADER)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          refute_predicate result, :success?
          assert_equal 2, result.batch_zuora_results.count
        end
      end

      test "records sponsorship metrics when updates include sponsorships" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        sponsor = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: sponsor)
        sponsor.stubs(:zuora_account).returns({})
        sponsorship = create(:sponsorship, sponsor: sponsor)
        tier = sponsorship.tier
        create(
          :billing_product_uuid,
          product_type: SponsorsTier::ZuoraDependency::ZUORA_PRODUCT_TYPE,
          product_key: tier.id.to_s,
          billing_cycle: sponsor.plan_duration,
        )

        params = test_update_params.merge(add: [], remove: [])
        update = params[:update].first
        update[:productRatePlanId] = tier.zuora_id(cycle: sponsor.plan_duration)
        stubbed_zuora_params = stub(
          update_params: params,
          github_rate_plans: []
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
        assert_predicate result, :success?

        assert_equal 1, GitHub.dogstats.increments("sponsors.zuora_subscription_update").length
      end

      test "does not record sponsorship metrics when updates do not include sponsorships" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        non_sponsor = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: non_sponsor)
        non_sponsor.stubs(:zuora_account).returns({})

        github_plan = non_sponsor.plan_subscription.plan
        params = test_update_params.merge(add: [], remove: [])
        update = params[:update].first
        update[:productRatePlanId] = github_plan.zuora_id(cycle: non_sponsor.plan_duration)
        stubbed_zuora_params = stub(
          update_params: params,
          github_rate_plans: []
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
        assert_predicate result, :success?

        assert_empty GitHub.dogstats.increments(
          "sponsors.zuora_subscription_update",
          tags: ["transition_enabled:false"]
        )
      end

      test "logs exceptions that are raised when calling the Zuora API" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        plan_subscription = create(:billing_plan_subscription, user: @pro_user)

        stubbed_zuora_params = stub(
          update_params: test_update_params,
          github_rate_plans: []
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        GitHub.zuorest_client.stubs(:update_subscription).raises(Zuorest::HttpError.new(504, "Gateway Timeout"))

        assert_raises Zuorest::HttpError do
          assert_logged("exception.type" => "Zuorest::HttpError", "exception.message" => "504 Gateway Timeout") do
            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          end
        end
        assert_equal 1, GitHub.dogstats.increments("zuora.zuorest.update_subscription.exception").length
      end

      test "overrides collect parameter when specified" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create(
          :billing_plan_subscription,
          user: user,
          zuora_subscription_id: "123",
          zuora_subscription_number: "A-123456"
        )

        fake_sub = Billing::Zuora::Subscription.new(plan_subscription.zuora_subscription_id, raw_subscription: {
          id: plan_subscription.zuora_subscription_id,
          subscriptionNumber: plan_subscription.zuora_subscription_number
        })
        fake_sub.stubs(plan_duration: user.plan_duration)
        Billing::Zuora::Subscription.stubs(:find).returns(fake_sub)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)

        [true, false].each do |collect|
          GitHub.zuorest_client.expects(:update_subscription).with(
            "A-123456",
            has_entry(collect: collect),
            Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
          ).returns(ZUORA_SUCCESS)

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, collect: collect).update
        end
      end

      test "includes extra dogstats tags when provided" do
        user = create(:credit_card_user, plan: "pro")
        plan_subscription = create(:billing_plan_subscription, user: user)
        user.stubs(:zuora_account).returns({})

        stubbed_zuora_params = stub(
          update_params: test_update_params,
          github_rate_plans: []
        )
        plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
        plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
        GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

        dogstats_tags = ["hello:world"]
        result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription, dogstats_tags: dogstats_tags).update
        assert_predicate result, :success?

        assert_dogstats_timing(1, "zuora.zuorest.update_subscription.timing", tags: dogstats_tags)
      end

      context "FF billing_sales_tax_workaround_for_subscription_updates" do
        test "sets the UpgradeCustomer field in Zuora to true and then false for eligible customers" do
          user = create(:credit_card_user, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, user: user)
          customer = user.customer
          customer.update(bill_cycle_day: (GitHub::Billing.today + 1.day).day)

          fake_zuora_account = Zuorest::Model::Account.new(
            success: true,
            basicInfo: {
              "id" => customer.zuora_account_id,
              "accountNumber" => customer.zuora_account_number,
              "status" => "Active",
            },
            billingAndPayment: {
              "billCycleDay" => 1,
              "autoPay" => true,
            },
            metrics: {},
            billToContact: {},
          )
          Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)
          Customer.any_instance.stubs(:eligible_for_sales_tax?).returns(true)

          if GitHub.flipper[:billing_sales_tax_workaround_for_subscription_updates].enabled?
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: true).once
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).once
          else
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: true).never
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).never
          end

          stubbed_zuora_params = stub(
            update_params: {
              applyCreditBalance: true,
              runBilling: true,
              collect: true,
              update: [{
                contractEffectiveDate: GitHub::Billing.today.to_s,
                ratePlanId: 42,
                chargeUpdateDetails: [{ quantity: 0, ratePlanChargeId: "8ad087d2917ed536019180913e174cc4" }]
              }],
              remove: [],
              add: []
            },
            github_rate_plans: []
          )
          plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
          plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
          GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          assert_predicate result, :success?
        end

        test "sets the UpgradeCustomer field in Zuora to false only for eligible customers on their bill cycle day" do
          user = create(:credit_card_user, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, user: user)
          customer = user.customer
          customer.update(bill_cycle_day: GitHub::Billing.today.day)

          fake_zuora_account = Zuorest::Model::Account.new(
            success: true,
            basicInfo: {
              "id" => customer.zuora_account_id,
              "accountNumber" => customer.zuora_account_number,
              "status" => "Active",
            },
            billingAndPayment: {
              "billCycleDay" => 1,
              "autoPay" => true,
            },
            metrics: {},
            billToContact: {},
          )
          Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)
          Customer.any_instance.stubs(:eligible_for_sales_tax?).returns(true)

          Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: true).never
          if GitHub.flipper[:billing_sales_tax_workaround_for_subscription_updates].enabled?
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).once
          else
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).never
          end

          stubbed_zuora_params = stub(
            update_params: {
              applyCreditBalance: true,
              runBilling: true,
              collect: true,
              update: [{
                contractEffectiveDate: GitHub::Billing.today.to_s,
                ratePlanId: 42,
                chargeUpdateDetails: [{ quantity: 0, ratePlanChargeId: "8ad087d2917ed536019180913e174cc4" }]
              }],
              remove: [],
              add: []
            },
            github_rate_plans: []
          )
          plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
          plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
          GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          assert_predicate result, :success?
        end

        test "sets the UpgradeCustomer field in Zuora to false only for eligible customers with no quantity updates" do
          user = create(:credit_card_user, plan: "pro")
          plan_subscription = create(:billing_plan_subscription, user: user)
          customer = user.customer
          customer.update(bill_cycle_day: GitHub::Billing.today.day)

          fake_zuora_account = Zuorest::Model::Account.new(
            success: true,
            basicInfo: {
              "id" => customer.zuora_account_id,
              "accountNumber" => customer.zuora_account_number,
              "status" => "Active",
            },
            billingAndPayment: {
              "billCycleDay" => 1,
              "autoPay" => true,
            },
            metrics: {},
            billToContact: {},
          )
          Zuorest::Model::Account.stubs(:find).returns(fake_zuora_account)
          Customer.any_instance.stubs(:eligible_for_sales_tax?).returns(true)

          Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: true).never
          if GitHub.flipper[:billing_sales_tax_workaround_for_subscription_updates].enabled?
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).once
          else
            Zuorest::Model::Account.any_instance.expects(:update!).with(UpgradeCustomer__c: false).never
          end

          stubbed_zuora_params = stub(
            update_params: test_update_params,
            github_rate_plans: []
          )
          plan_subscription.stubs(:zuora_params).returns(stubbed_zuora_params)
          plan_subscription.stubs(:update_from_zuora_subscription).returns(true)
          GitHub.zuorest_client.stubs(:update_subscription).returns(ZUORA_SUCCESS)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).update
          assert_predicate result, :success?
        end
      end
    end

    context "#cancel" do
      context "and billing for Actions is enabled" do
        test "cancels user subscription" do
          pro_user = T.must(@pro_user)
          zuora_successful_customer_account_creation(pro_user)

          with_live_zuora("zuora_subscription/billing_github_actions/cancel_subscription") do
            listing = create(:marketplace_listing, :verified)
            listing_plan = create :marketplace_listing_plan, :published,
              per_unit: true,
              unit_name: "Seats",
              listing: listing

            listing_plan.sync_to_zuora
            pro_user.reload
            plan_subscription = T.must(pro_user.plan_subscription)
            create :billing_subscription_item,
              subscribable: listing_plan,
              plan_subscription: plan_subscription,
              quantity: 4
            pending_plan_change = create(:billing_pending_plan_change, user: pro_user)
            create :billing_pending_subscription_item_change, pending_plan_change: pending_plan_change, subscribable: listing_plan, quantity: 3
            assert_equal 1, pro_user.pending_subscription_item_changes.count

            Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

            zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
            assert_equal 3, zuora_sub.active_rate_plans.count

            zuora_subscription_number = plan_subscription.zuora_subscription_number
            result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).cancel
            assert_predicate result, :success?

            zuora_sub = Billing::Zuora::Subscription.find!(zuora_subscription_number)
            assert_equal 0, zuora_sub.active_rate_plans.count
            assert_equal 3, zuora_sub.cancelled_rate_plans.count
            assert_equal "Cancelled", zuora_sub.status
            refute plan_subscription.reload.zuora_subscription_number?
            assert_predicate plan_subscription, :cancelled_or_non_zuora?
            assert_equal 1, pro_user.reload.pending_subscription_item_changes.count
          end
        end
      end

      test "cancels user's Zuora subscription and active, paid subscription items" do
        pro_user = T.must(@pro_user)
        zuora_successful_customer_account_creation(pro_user)
        pro_user.reload

        with_live_zuora("zuora_subscription/cancel_subscription") do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create :marketplace_listing_plan, :published,
            per_unit: true,
            unit_name: "Seats",
            listing: listing

          listing_plan.sync_to_zuora
          plan_subscription = T.must(pro_user.plan_subscription)
          create :billing_subscription_item,
            subscribable: listing_plan,
            plan_subscription: plan_subscription,
            quantity: 4

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
          assert_equal 2, zuora_sub.active_rate_plans.count

          zuora_subscription_number = plan_subscription.zuora_subscription_number
          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).cancel
          assert_predicate result, :success?

          zuora_sub = Billing::Zuora::Subscription.find!(zuora_subscription_number)
          assert_equal 0, zuora_sub.active_rate_plans.count
          assert_equal 2, zuora_sub.cancelled_rate_plans.count
          assert_equal "Cancelled", zuora_sub.status
          refute plan_subscription.reload.zuora_subscription_number?
          assert_predicate plan_subscription, :cancelled_or_non_zuora?
          assert plan_subscription.active_subscription_items.none?
        end
      end

      test "does not cancel sub items or pending subscription item changes on other plan subscriptions" do
        pro_user = T.must(@pro_user)
        zuora_successful_customer_account_creation(pro_user)
        pro_user.reload

        with_live_zuora("zuora_subscription/cancel_subscription") do
          listing = create(:marketplace_listing, :verified)
          listing_plan = create :marketplace_listing_plan, :published,
            per_unit: true,
            unit_name: "Seats",
            listing: listing

          listing_plan.sync_to_zuora
          plan_subscription = T.must(pro_user.plan_subscription)
          copilot_product_uuid = create(:billing_product_uuid, :copilot)

          create :billing_subscription_item, subscribable: listing_plan, plan_subscription: plan_subscription, quantity: 4
          create :billing_subscription_item, subscribable: copilot_product_uuid, plan_subscription: plan_subscription, quantity: 1
          pending_plan_change = create(:billing_pending_plan_change, user: pro_user)
          create :billing_pending_subscription_item_change, plan_subscription: plan_subscription, pending_plan_change: pending_plan_change, subscribable: listing_plan, quantity: 3
          create :billing_pending_subscription_item_change, plan_subscription: plan_subscription, pending_plan_change: pending_plan_change, subscribable: copilot_product_uuid

          sponsors_plan_subscription = create(:billing_plan_subscription, :sponsors_invoiced,
            customer: pro_user.customer,
            user: pro_user
          )
          sponsors_sub_item = create(:sponsors_subscription_item,
            plan_subscription: sponsors_plan_subscription,
          )
          create :sponsors_pending_subscription_item_change, plan_subscription: sponsors_plan_subscription, pending_plan_change: pending_plan_change
          assert_equal 3, pro_user.pending_subscription_item_changes.count

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

          zuora_sub = Billing::Zuora::Subscription.find!(plan_subscription.reload.zuora_subscription_number)
          assert_equal 2, zuora_sub.active_rate_plans.count

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).cancel
          assert_predicate result, :success?

          assert_predicate sponsors_sub_item.reload, :active?
          assert_equal 2, pro_user.reload.pending_subscription_item_changes.count
          assert_predicate plan_subscription, :cancelled_or_non_zuora?
          assert_empty pro_user.pending_subscription_item_changes.select { |item_changes| item_changes.subscribable == copilot_product_uuid }
        end
      end

      test "returns success when zuora subscription doesn't exist" do
        with_live_zuora("zuora/find_nonexistent_subscription") do
          plan_subscription = create :billing_plan_subscription, :zuora, user: @pro_user,
            zuora_subscription_number: "A-S1234567"

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).cancel

          assert result.success?
          refute plan_subscription.reload.zuora_subscription_number?
          assert_predicate plan_subscription, :cancelled_or_non_zuora?
        end
      end

      test "does not remove protected branches for a user with a free private repo" do
        GitHub.flipper[:pages_soft_deletion].disable
        with_live_zuora("zuora_subscription/cancel_subscription_with_gated_feature") do
          pro_user = T.must(@pro_user)
          repo = create :private_repository, owner: pro_user
          create :page, repository: repo
          create :protected_branch, repository: repo

          assert repo.page
          refute_empty repo.protected_branches

          zuora_successful_customer_account_creation(pro_user)
          pro_user.update_column(:plan, "free")
          pro_user.reload
          plan_subscription = T.must(pro_user.plan_subscription)

          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).cancel
          repo.reload

          assert result.success?
          assert_nil repo.page
          refute_empty repo.protected_branches
          assert_predicate plan_subscription.reload, :cancelled_or_non_zuora?
        end
      end

      test "caches the outstanding balance and records metrics" do
        pro_user = T.must(@pro_user)
        zuora_successful_customer_account_creation(pro_user)
        pro_user.reload

        with_live_zuora("zuora_subscription/cancel_subscription") do
          plan_subscription = T.must(pro_user.plan_subscription)
          plan_subscription.update(balance_in_cents: 2500)

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).create

          zuora_subscription_number = plan_subscription.zuora_subscription_number
          result = Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription.reload).cancel

          assert_predicate result, :success?
          assert_equal 25, plan_subscription.cached_outstanding_balance_from_last_cancelled_zuora_subscription
          assert_dogstats_count_value 25, "billing.plan_subscription.outstanding_balance"
        end
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def test_create_params
      {
        accountKey: "KEY",
        contractEffectiveDate: GitHub::Billing.today.to_s,
        termType: "EVERGREEN",
        subscribeToRatePlans: [],
        runBilling: true,
        collect: true,
      }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def test_update_params
      {
        applyCreditBalance: true,
        runBilling: true,
        collect: true,
        update: [{
          contractEffectiveDate: GitHub::Billing.today.to_s,
          ratePlanId: 42,
          chargeUpdateDetails: {}
        }],
        remove: [{
          contractEffectiveDate: GitHub::Billing.today.to_s,
          ratePlanId: 43,
        }],
        add: [{
          contractEffectiveDate: GitHub::Billing.today.to_s,
          productRatePlanId: 44,
          chargeOverrides: [],
        }]
      }
    end

    sig { returns(String) }
    def api_version
      "zuora_subscription"
    end
  end
end
