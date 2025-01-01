# typed: true
# frozen_string_literal: true

if GitHub.billing_enabled?
  require "test_helper"

  class Billing::HelpHubEligibilityTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper
    include DogstatsTestHelpers
    include ::Billing::ApiTestHelpers

    setup do
      synchronize_github_products_to_zuora

      rate_plan_charge = attributes_for(:zuora_rate_plan_charge)
      rate_plan_charge[:chargedThroughDate] = 10.days.from_now.strftime("%Y-%m-%d")
      @raw_zuora_sub = attributes_for(:zuora_subscription, :active, ratePlans: [{
        ratePlanCharges: [rate_plan_charge]
      }])
      @copilot_product_uuid = create :billing_product_uuid,
        :copilot,
        billing_cycle: :month,
        zuora_product_rate_plan_charge_ids: { flat: rate_plan_charge[:productRatePlanChargeId] }
      @plan_subscription = create(:billing_plan_subscription, :zuora, zuora_rate_plan_charges: {
        rate_plan_charge[:productRatePlanChargeId] => {
          number: rate_plan_charge[:number],
          charged_through_date: Date.parse(rate_plan_charge[:chargedThroughDate])
        }
      })
      create(:plan_subscription_zuora_rate_plan_charge, payload: rate_plan_charge, plan_subscription: @plan_subscription)
      @user = @plan_subscription.user

      zuora_subscription = begin
        GitHub.zuorest_client.expects(:get_subscription).with("test").returns(@raw_zuora_sub)
        Billing::Zuora::Subscription.find("test")
      ensure
        GitHub.zuorest_client.unstub(:get_subscription)
      end
      @copilot_subscription_item = create :billing_subscription_item,
        :paid, plan_subscription: @plan_subscription,
        subscribable: @copilot_product_uuid
      @copilot_subscription_item.plan_subscription.stubs(:external_subscription).returns(zuora_subscription)
    end

    context "#eligible_based_on_usage_products?" do
      test "returns false if no metered_billing_configuration, and no LFS" do
        user = create(:credit_card_user)
        eligibility_check = ::Billing::HelpHubEligibility.new(account: user)

        eligibility_check.expects(:codespaces_customer?).once
        refute eligibility_check.eligible_based_on_usage_products?
      end

      test "returns false if they've not set up a budget and havent purchased LFS" do
        user = create(:credit_card_user)
        eligibility_check = ::Billing::HelpHubEligibility.new(account: user)

        refute eligibility_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"

        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
        # Does not have a metered billing configuration set up for overages
        assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
      end

      test "returns false if they've set up a configuration enforcing a spending limit of zero subunits" do
        user = create(:credit_card_user)

        # This is the default, but I'm being explicit
        create(:billing_budget, owner: user, enforce_spending_limit: true, spending_limit_in_subunits: 0)

        eligibility_check = ::Billing::HelpHubEligibility.new(account: user)
        refute eligibility_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"

        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
        # Does not have a metered billing configuration set up for overages
        assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
      end

      test "returns false if user does not have an external_subscription" do
        user = create(:user)
        refute user.plan_subscription&.external_subscription?

        eligibility_check = ::Billing::HelpHubEligibility.new(account: user)
        refute eligibility_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"

        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
        # Does not have a metered billing configuration set up for overages
        assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
      end

      test "returns true if they've paid for a data pack in the last two cycles" do
        travel_to(::GitHub::Billing.date_in_timezone(Date.new(2020, 05, 02))) do
          lfs_txn = create(:billing_transaction, created_at: ::GitHub::Billing.now - 2.months, asset_packs_total: 1)
          has_lfs_user = lfs_txn.user
          has_lfs_check = ::Billing::HelpHubEligibility.new(account: has_lfs_user)

          non_lfs_txn = create(:billing_transaction, created_at: ::GitHub::Billing.now - 2.months)
          non_lfs_user = non_lfs_txn.user
          non_lfs_check = ::Billing::HelpHubEligibility.new(account: non_lfs_user)

          year_txn = create(:billing_transaction, created_at: ::GitHub::Billing.now - 1.year, asset_packs_total: 1)
          year_user = year_txn.user
          year_check = ::Billing::HelpHubEligibility.new(account: year_user)

          assert has_lfs_check.eligible_based_on_usage_products?
          refute non_lfs_check.eligible_based_on_usage_products?
          refute year_check.eligible_based_on_usage_products?

          assert_dogstats_timing 3, "billing.help_hub_eligibility"
          assert_dogstats_timing 3, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 3, "billing.help_hub_eligibility.recent_usage"
          assert_dogstats_timing 3, "billing.help_hub_eligibility.metered_billing_customer_queries"
          assert_dogstats_timing 3, "billing.help_hub_eligibility.lfs_customer_queries"
          assert_dogstats_timing 3, "billing.help_hub_eligibility.recent_lfs_usage"

          # Does not have an external_subscription so we early return
          assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
          # Does not have a metered billing configuration set up for overages
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        end
      end

      test "returns true if a yearly user paid for lfs a year ago" do
        travel_to(::GitHub::Billing.date_in_timezone(Date.new(2020, 05, 02))) do
          user = create(:user, plan_duration: "year")
          create(:billing_transaction, user: user, created_at: ::GitHub::Billing.now - 1.year, asset_packs_total: 1)
          user_check = ::Billing::HelpHubEligibility.new(account: user)

          user_with_lfs_outside_one_year = create(:user, plan_duration: "year")
          create(:billing_transaction, user: user_with_lfs_outside_one_year, created_at: ::GitHub::Billing.now - 1.year - 1.day, asset_packs_total: 1)
          with_lfs_outside_one_year_check = ::Billing::HelpHubEligibility.new(account: user_with_lfs_outside_one_year)

          user.reload
          user_with_lfs_outside_one_year.reload

          assert user_check.eligible_based_on_usage_products?
          refute with_lfs_outside_one_year_check.eligible_based_on_usage_products?

          assert_dogstats_timing 2, "billing.help_hub_eligibility"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.recent_usage"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.metered_billing_customer_queries"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.lfs_customer_queries"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.recent_lfs_usage"

          # Does not have an external_subscription so we early return
          assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
          # Does not have a metered billing configuration set up for overages
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        end
      end

      test "returns true if they've paid for metered billing in the last two months" do
        travel_to(::GitHub::Billing.date_in_timezone(Date.new(2020, 05, 02))) do
          within_two_months_user = create(:user)
          within_transaction = create(
            :billing_transaction,
            :zuora,
            user: within_two_months_user,
            created_at: ::GitHub::Billing.now - 2.months
          )
          _within_line_item = create(
            :billing_transaction_line_item,
            :actions_private_usage,
            billing_transaction: within_transaction,
            created_at: ::GitHub::Billing.now - 2.months
          )

          outside_two_months_user = create(:user)
          outside_transaction = create(
            :billing_transaction,
            :zuora,
            user: outside_two_months_user,
            created_at: ::GitHub::Billing.now - 2.months - 1.day
          )
          _outside_line_item = create(
            :billing_transaction_line_item,
            :actions_private_usage,
            billing_transaction: outside_transaction,
            created_at: ::GitHub::Billing.now - 2.months - 1.day
          )

          within_two_months_check = ::Billing::HelpHubEligibility.new(account: within_two_months_user)
          assert within_two_months_check.eligible_based_on_usage_products?

          outside_two_months_check = ::Billing::HelpHubEligibility.new(account: outside_two_months_user)
          refute outside_two_months_check.eligible_based_on_usage_products?

          assert_dogstats_timing 2, "billing.help_hub_eligibility"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.recent_usage"

          # Only recorded timing for the `outside_two_months_user`, because `within_two_months_user`
          # returns early with a true value
          assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"

          # Does not have an external_subscription so we early return
          assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
          # Does not have a metered billing configuration set up for overages
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        end
      end

      test "returns true if it looks like we will charge them at the end of the month for storage" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        mock_list_product_usage_response(product: "shared_storage", quantity: 100.gigabytes)

        travel_to(user.current_metered_billing_cycle_starts_at) do
          create(:shared_storage_current_usage, :private_visibility, owner: user, billable_owner: user, aggregate_size_in_bytes: 100.gigabytes)
          user_check = ::Billing::HelpHubEligibility.new(account: user)

          assert user_check.eligible_based_on_usage_products?

          assert_dogstats_timing 1, "billing.help_hub_eligibility"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"

          # Return before codespaces checks
          assert_dogstats_timing 0, "billing.help_hub_eligibility.codespaces_customer_queries"
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_codespaces_usage_will_be_billed"
          # Return before getting to LFS checks
          assert_dogstats_timing 0, "billing.help_hub_eligibility.lfs_customer_queries"
          assert_dogstats_timing 0, "billing.help_hub_eligibility.recent_lfs_usage"
          # Does not have an external_subscription so we early return
          assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
        end
      end

      test "returns true if it looks like we will charge them at the end of the month for codespaces" do
        user = create(:credit_card_user)

        create(:billing_budget, :codespaces, owner: user)
        mock_calculate_usage_quotes_response(total_historical_usage_estimated_cost: 100)
        user_check = ::Billing::HelpHubEligibility.new(account: user)

        assert user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.codespaces_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_codespaces_usage_will_be_billed"

        # No budget for metered billing shared product
        assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"

        # Codespaces check is prior to LFS queries
        assert_dogstats_timing 0, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 0, "billing.help_hub_eligibility.recent_lfs_usage"
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns true if paid for codespaces usage in the last two months" do
        travel_to(::GitHub::Billing.date_in_timezone(Date.new(2020, 05, 02))) do
          within_two_months_user = create(:user)
          within_transaction = create(
            :billing_transaction,
            :zuora,
            user: within_two_months_user,
            created_at: ::GitHub::Billing.now - 2.months
          )
          _within_line_item = create(
            :billing_transaction_line_item,
            :codespaces_compute_d2_usage,
            billing_transaction: within_transaction,
            created_at: ::GitHub::Billing.now - 2.months
          )

          outside_two_months_user = create(:user)
          outside_transaction = create(
            :billing_transaction,
            :zuora,
            user: outside_two_months_user,
            created_at: ::GitHub::Billing.now - 2.months - 1.day
          )
          _outside_line_item = create(
            :billing_transaction_line_item,
            :codespaces_compute_d2_usage,
            billing_transaction: outside_transaction,
            created_at: ::GitHub::Billing.now - 2.months - 1.day
          )

          within_two_months_check = ::Billing::HelpHubEligibility.new(account: within_two_months_user)
          assert within_two_months_check.eligible_based_on_usage_products?

          outside_two_months_check = ::Billing::HelpHubEligibility.new(account: outside_two_months_user)
          refute outside_two_months_check.eligible_based_on_usage_products?

          assert_dogstats_timing 2, "billing.help_hub_eligibility"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 2, "billing.help_hub_eligibility.recent_usage"

          # Only recorded timing for the `outside_two_months_user`, because `within_two_months_user`
          # returns early with a true value
          assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"

          # Does not have an external_subscription so we early return
          assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
          # Does not have a metered billing configuration set up for overages
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_codespaces_usage_will_be_billed"
        end
      end

      test "returns true if it looks like we will charge them at the end of the month for actions" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        minutes_used = (100.hours / 60.0).to_f
        mock_list_product_usage_response(product: "actions", sku_name: "linux", quantity: minutes_used)
        user_check = ::Billing::HelpHubEligibility.new(account: user)

        assert user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"

        # Return before getting to LFS checks
        assert_dogstats_timing 0, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 0, "billing.help_hub_eligibility.recent_lfs_usage"
        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns true if it looks like we will charge them at the end of the month for package bandwidth" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        mock_list_product_usage_response(product: "packages", sku_name: "default", quantity: 50.gigabytes)
        user_check = ::Billing::HelpHubEligibility.new(account: user)

        assert user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"

        # Return before getting to LFS checks
        assert_dogstats_timing 0, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 0, "billing.help_hub_eligibility.recent_lfs_usage"
        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns false if billing-api has an error for packages and there is no other usage" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        ::Billing::PackageRegistryUsage.any_instance.stubs(:has_error?).returns(true)

        user_check = ::Billing::HelpHubEligibility.new(account: user)

        refute user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"
        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns false if billing-api has an error for storage and there is no other usage" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        ::Billing::SharedStorageUsage.any_instance.stubs(:has_error?).returns(true)

        user_check = ::Billing::HelpHubEligibility.new(account: user)

        refute user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"
        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns false if billing-api has an error for actions and there is no other usage" do
        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        ::Billing::ActionsUsage.any_instance.stubs(:has_error?).returns(true)

        user_check = ::Billing::HelpHubEligibility.new(account: user)

        refute user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"
        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
      end

      test "returns false if user does not have a valid payment method, but has racked up enough usage to be charged" do

        user = create(:credit_card_user)
        create(:billing_budget, owner: user)
        mock_calculate_usage_quotes_response(total_proposed_usage_effective_quantity: 50.gigabytes)

        user.payment_method.destroy
        user.reload

        user_check = ::Billing::HelpHubEligibility.new(account: user)
        refute user_check.eligible_based_on_usage_products?

        assert_dogstats_timing 1, "billing.help_hub_eligibility"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
        assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"

        # Does not have an external_subscription so we early return
        assert_dogstats_timing 0, "billing.help_hub_eligibility.external_subscription_lfs_check"
        # No metered billing configuration so we dont check for current usage
        assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
      end

      test "returns true if user has an active subscription with data packs" do
        with_live_zuora("zuora_subscription/create_subscription_for_lfs_user") do
          zuora_user = create(:user)
          Asset::Status.create(owner: zuora_user, asset_packs: 3)

          zuora_successful_customer_account_creation(zuora_user)
          zuora_user.reload
          plan_subscription = zuora_user.plan_subscription

          Billing::PlanSubscription::ZuoraSynchronizer.new(plan_subscription).create
          zuora_user.reload

          zuora_user_check = ::Billing::HelpHubEligibility.new(account: zuora_user)
          assert zuora_user_check.eligible_based_on_usage_products?

          assert_dogstats_timing 1, "billing.help_hub_eligibility"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.usage_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_usage"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.metered_billing_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.lfs_customer_queries"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.recent_lfs_usage"
          assert_dogstats_timing 1, "billing.help_hub_eligibility.external_subscription_lfs_check"

          # No metered billing configuration so we dont check for current usage
          assert_dogstats_timing 0, "billing.help_hub_eligibility.current_metered_usage_will_be_billed"
        end
      end
    end

    context "#helphub_copilot_refund_eligibality" do
      test "returns ineligible if not a user" do
        r = Billing::HelpHubEligibility.new(account: create(:organization)).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_includes r[:ineligibility_reasons], "not_a_user"
      end

      test "returns ineligible if spammy" do
        r = Billing::HelpHubEligibility.new(account: create(:spammy_user)).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_includes r[:ineligibility_reasons], "user_flagged"
      end

      test "returns ineligible if no subscription" do
        r = Billing::HelpHubEligibility.new(account: create(:user)).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_equal r[:ineligibility_reasons], "no_eligible_subscriptions_found charge_not_found"
      end

      test "returns ineligible if refunded in the last 2 years" do
        billing_transaction = create :billing_transaction,
          amount_in_cents: 10_00,
          plan_name: "free_with_addons",
          plan_price_in_cents: 0,
          created_at: Time.now - 727.days
        create :billing_transaction_line_item,
          :copilot_for_individual_month,
          user: @user,
          quantity: 1,
          amount_in_cents: 10_00,
          billing_transaction: billing_transaction,
          subscribable: @copilot_product_uuid
        refund_transaction = create :billing_transaction, :refund,
          amount_in_cents: 7_83,
          sale_transaction_id: billing_transaction.transaction_id,
          user: @user

        r = Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_equal r[:ineligibility_reasons], "recently_refunded"
      end

      test "return ineligible if not charged in last 31 days" do
        billing_transaction = create :billing_transaction, :failed,
          amount_in_cents: 10_00,
          plan_name: "free_with_addons",
          plan_price_in_cents: 0,
          created_at: Time.now - 32.days
        create :billing_transaction_line_item,
          :copilot_for_individual_month,
          user: @user,
          quantity: 1,
          amount_in_cents: 10_00,
          billing_transaction: billing_transaction,
          subscribable: @copilot_product_uuid

        r = Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_equal r[:ineligibility_reasons], "charge_not_found"
      end

      test "return ineligible if total charge is too much" do
        billing_transaction = create :billing_transaction,
          amount_in_cents: 140_00,
          plan_name: "free_with_addons",
          plan_price_in_cents: 0,
          created_at: Time.now - 2.days
        create :billing_transaction_line_item,
          :copilot_for_individual_month,
          user: @user,
          quantity: 1,
          amount_in_cents: 140_00,
          billing_transaction: billing_transaction,
          subscribable: @copilot_product_uuid

        r = Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility
        refute r[:eligible]
        assert_equal r[:ineligibility_reasons], "charge_not_found_under_amount"
      end

      test "return eligible" do
        billing_transaction = create :billing_transaction,
          amount_in_cents: 10_00,
          plan_name: "free_with_addons",
          plan_price_in_cents: 0,
          created_at: Time.now - 2.days
        create :billing_transaction_line_item,
          :copilot_for_individual_month,
          user: @user,
          quantity: 1,
          amount_in_cents: 10_00,
          billing_transaction: billing_transaction,
          subscribable: @copilot_product_uuid

        assert_equal Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility,
          {
            product: "copilot_individual",
            eligible: true,
            ineligibility_reasons: "",
            subscription_item_id: @copilot_subscription_item.id
          }
      end

      test "return eligible for pending cancellation" do
        billing_transaction = create :billing_transaction,
          amount_in_cents: 10_00,
          plan_name: "free_with_addons",
          plan_price_in_cents: 0,
          created_at: Time.now - 2.days
        create :billing_transaction_line_item,
          :copilot_for_individual_month,
          user: @user,
          quantity: 1,
          amount_in_cents: 10_00,
          billing_transaction: billing_transaction,
          subscribable: @copilot_product_uuid

        Zuorest::RestClient.any_instance.stubs(:get_subscription).returns(@raw_zuora_sub)
        GitHub.zuorest_client.stubs(:get_subscription).returns(@raw_zuora_sub)
        perform_enqueued_jobs only: [SynchronizePlanSubscriptionJob, RunPendingPlanChangeJob] do
          @copilot_subscription_item.cancel!(actor: @user, force: false)
        end

        assert Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility[:eligible]
        @user.incomplete_pending_plan_changes.first.run
        refute Billing::HelpHubEligibility.new(account: @user).helphub_copilot_refund_eligibility[:eligible]
      end
    end

    context "#helphub_downgradable_products" do
      test "returns array including copilot individual if user pays for copilot individual" do
        product_uuid = create :billing_product_uuid,
          :copilot, billing_cycle: :month
        plan_subscription = create(:billing_plan_subscription)
        create :billing_subscription_item,
          :paid, plan_subscription: plan_subscription, subscribable: product_uuid

        assert_same_elements [{ "type": "copilot_individual" }], Billing::HelpHubEligibility.new(account: plan_subscription.user).helphub_downgradable_products
      end

      test "returns array without copilot individual if user has copilot individual trial" do
        product_uuid = create :billing_product_uuid,
          :copilot, billing_cycle: :month
        plan_subscription = create(:billing_plan_subscription)
        create :billing_subscription_item,
          :free_trial,
          plan_subscription: plan_subscription,
          subscribable: product_uuid,
          free_trial_ends_on: GitHub::Billing.today + 14.days

        assert_same_elements [], Billing::HelpHubEligibility.new(account: plan_subscription.user).helphub_downgradable_products
      end

      test "returns array without copilot individual if user has no active copilot individual subscription" do
        plan_subscription = create(:billing_plan_subscription)
        create :billing_subscription_item,
          :paid, plan_subscription: plan_subscription

        assert_same_elements [], Billing::HelpHubEligibility.new(account: plan_subscription.user).helphub_downgradable_products
      end
    end
  end
end
