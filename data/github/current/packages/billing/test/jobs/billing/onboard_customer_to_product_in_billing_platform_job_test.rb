# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module Billing
  class OnboardCustomerToProductInBillingPlatformJobTest < GitHub::TestCase
    include JobTestHelper

    fixtures do
      @customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:business, customer: @customer)
      create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, customer: @customer)
    end

    setup do
      enable_feature_flag(:unbundle_ghas_for_new_org_ent)
    end

    test "job does not raise and retry if no billable owner is present" do
      Customer.any_instance.stubs(:billable_owner).returns(nil)

      assert_no_enqueued_jobs(only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
        Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(
          customer_id: T.must(@customer.id),
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
              Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
              Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
              Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
              Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
        )
      end
    end

    test "performs the actions to onboard actions for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize)
      assert @customer.billing_platform_enabled_product.actions
    end

    test "performs the actions to onboard codespaces for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize)
      assert @customer.billing_platform_enabled_product.codespaces
    end

    test "performs the actions to onboard copilot for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize)
      assert @customer.billing_platform_enabled_product.copilot
    end

    test "performs the actions to onboard copilot for customer with daily emissions" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize)
      assert @customer.billing_platform_enabled_product.copilot
    end

    test "performs the actions to onboard GHAS for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      assert @customer.billing_platform_enabled_product.ghas
      assert T.must(@customer.business).reload.advanced_security_metered_for_entity?
      refute @customer.business.advanced_security_products_bundled?
    end

    # This test can eventually be removed when unbundle_ghas_for_new_org_ent is removed
    test "performs the actions to onboard GHAS for customer, as an bundled offering" do
      disable_feature_flag(:unbundle_ghas_for_new_org_ent)

      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      assert @customer.billing_platform_enabled_product.ghas
      assert T.must(@customer.business).reload.advanced_security_metered_for_entity?
      assert @customer.business.advanced_security_products_bundled?
    end

    # This test can eventually be removed when unbundle_ghas_for_new_org_ent is removed
    test "does not perform the actions to onboard GHAS for user customer" do
      disable_feature_flag(:unbundle_ghas_for_new_org_ent)

      @customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, customer: @customer)
      org = create(:organization, customer: @customer)
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      refute @customer.billing_platform_enabled_product.ghas
    end

    test "does perform the actions to onboard GHAS for org customer" do
      @customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, customer: @customer)
      org = create(:organization, customer: @customer, plan: GitHub::Plan.business)

      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      assert @customer.billing_platform_enabled_product.ghas
      assert org.reload.advanced_security_metered_for_entity?
      refute org.advanced_security_products_bundled?
    end

    test "does not onboard GHAS for free org" do
      @customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, customer: @customer)
      org = create(:organization, customer: @customer, plan: GitHub::Plan.free)

      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      refute @customer.billing_platform_enabled_product.ghas
      refute org.reload.advanced_security_metered_for_entity?
    end

    test "performs the actions to onboard GHAS for customer who already has volume billing" do
      @customer.business.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
      @customer.business.set_advanced_security_seats_for_entity(seats: 100, actor: User.ghost, is_stafftools_action: true)

      business = @customer.business.reload
      assert business.advanced_security_purchased_for_entity?
      refute business.advanced_security_metered_for_entity?
      refute business.advanced_security_license.unlimited_seats?

      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize)
      assert @customer.billing_platform_enabled_product.ghas

      business = @customer.business.reload
      assert business.advanced_security_purchased_for_entity?
      assert business.advanced_security_metered_for_entity?
      assert business.advanced_security_license.unlimited_seats?
    end

    test "performs the actions to onboard GHEC for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize)
      assert @customer.billing_platform_enabled_product.ghec
    end

    test "does not perform the actions to onboard GHEC for user customer" do
      @customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:billing_plan_subscription, :zuora, balance_in_cents: 7_00, customer: @customer)
      org = create(:organization, customer: @customer)
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize)
      refute @customer.billing_platform_enabled_product.ghec
    end

    test "performs the actions to onboard LFS for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize)
      assert @customer.billing_platform_enabled_product.git_lfs
    end

    test "updates the customers migration date if it hasn't been set yet" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize)

      assert @customer.billing_platform_enabled_product.migration_date
    end

    test "doesnt update migration date if it already previously updated" do
      freeze_time do
        original_migration_date = 3.days.ago

        create(:billing_platform_enabled_product, customer: @customer, migration_date: original_migration_date)
        successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize)

        assert_equal @customer.billing_platform_enabled_product.migration_date, original_migration_date
      end
    end

    test "performs the actions to onboard packages for customer" do
      successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize)
      assert @customer.billing_platform_enabled_product.packages
    end

    test "does not queue budget migration job for vNext native business customer" do
      assert_no_enqueued_jobs(only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize)
      end
    end

    test "enqueues budget migration job for non-vnext native customer" do
      @customer.update(created_at: Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE - 1.day)
      assert_enqueued_jobs(1, only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        successful_onboarding_of_product(product: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize)
      end
    end

    test "does not queue budget migration job for vNext native Team plan customer if 'default_zero_budget_for_all_individuals_and_orgs' is disabled" do
      disable_feature_flag(:default_zero_budget_for_all_individuals_and_orgs)
      customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:organization, plan: :business, customer: customer)
      customer.update!(billed_via_billing_platform: true)

      assert_no_enqueued_jobs(only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(customer_id: T.must(customer.id), products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize])
      end
    end

    test "enqueues budget migration job for vNext native Team plan customer if 'default_zero_budget_for_all_individuals_and_orgs' is enabled" do
      enable_feature_flag(:default_zero_budget_for_all_individuals_and_orgs)
      customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:organization, plan: :business, customer: customer)
      customer.update!(billed_via_billing_platform: true)

      assert_enqueued_jobs(1, only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        assert_enqueued_with(job: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob, args: [customer, true]) do
          Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(customer_id: T.must(customer.id), products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize])
        end
      end
    end

    test "enqueues budget migration job for vNext native free organization customer" do
      customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
      create(:organization, plan: :free, customer: customer)
      customer.update!(billed_via_billing_platform: true)

      assert_enqueued_jobs(1, only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(customer_id: T.must(customer.id), products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize])
      end
    end

    test "enqueues budget migration job for vNext native individual customer with feature flag on" do
      assert_enqueued_jobs(1, only: Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob) do
        customer = create(:credit_card_customer, billing_type: "card", bill_cycle_day: 20)
        user = create(:user, customer: customer)
        customer.update!(billed_via_billing_platform: true)

        Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(customer_id: T.must(customer.id), products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize])
      end
    end

    test "we record a failure if something raises" do
      config = create(:billing_platform_enabled_product, failed_at: nil, customer: @customer)
      product = Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize

      Billing::UpdateCustomerInBillingPlatformJob.stubs(:perform_now).with(@customer, nil).raises(StandardError.new("boom"))

      assert_nil config.failed_at

      GitHub.logger.expects(:error).at_least_once

      enable_product_for_customer(customer: @customer, products: [product])

      refute_nil config.reload.failed_at

      target_jobs = enqueued_jobs.select { |job| job["job_class"] == "Billing::OnboardCustomerToProductInBillingPlatformJob" }
      assert_equal 1, target_jobs.count
      assert_equal 1, target_jobs.first["executions"]
    end

    test "we mark a previously failed migration as completed if retry is successful" do
      product = Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize
      config = create(:billing_platform_enabled_product, failed_at: Time.zone.now, customer: @customer)

      refute_nil config.failed_at
      assert_nil config.migration_date

      enable_product_for_customer(customer: @customer, products: [product])

      assert_nil config.reload.failed_at
      refute_nil config.migration_date
    end

    test "retry conditions" do
      assert_retry_on_recoverable_exceptions job: Billing::OnboardCustomerToProductInBillingPlatformJob
      assert_retry_on_dirty_exit job: Billing::OnboardCustomerToProductInBillingPlatformJob, args: []
      assert_retry_on_error Zuorest::TooManyRequestsError, Billing::OnboardCustomerToProductInBillingPlatformJob, []
    end

    test "updates rate plan charges" do
      travel_to(GitHub::Billing.timezone.local(2024, 7, 1)) do
        FakeZuora.mock

        rate_plan_id = SecureRandom.uuid
        product_rate_plan_id = SecureRandom.uuid
        product_rate_plan_charge_id = SecureRandom.uuid

        raw_subscription = attributes_for(:zuora_subscription, :active, ratePlans: [{
          id: rate_plan_id,
          productRatePlanId: product_rate_plan_id,
          productName: "GitHub Actions",
          ratePlanCharges: [
            {
              productRatePlanChargeId: product_rate_plan_charge_id,
              name: "GitHub Actions Usage",
              price: 1.0,
              type: "Usage",
              billingDay: "DefaultFromCustomer",
              effectiveEndDate: nil,
              chargedThroughDate: "2024-01-01",
              billingPeriod: "Month"
            },
          ],
        }])

        plan_subscription = @customer.plan_subscription
        GitHub.zuorest_client.expects(:get_subscription).with(plan_subscription.zuora_subscription_number).returns(raw_subscription)
        subscription = Billing::Zuora::Subscription.find!(plan_subscription.zuora_subscription_number)

        Billing::PlanSubscription.any_instance.stubs(:zuora_subscription).returns(subscription)
        Billing::PlanSubscription.any_instance.stubs(:update_from_zuora_subscription).returns(true)

        rate_plan_changes = [{
          contractEffectiveDate: "2024-07-01",
          ratePlanId: rate_plan_id,
          newProductRatePlanId: product_rate_plan_id,
          chargeOverrides: [{
            productRatePlanChargeId: product_rate_plan_charge_id,
            billCycleType: "SpecificDayofMonth",
            billingPeriodAlignment: "AlignToCharge",
            billCycleDay: 1
          }]
        }]

        GitHub.zuorest_client.expects(:update_subscription).with(
          subscription.number, { change: rate_plan_changes },
          Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
        ).once

        enable_product_for_customer(
          customer: @customer,
          products: [Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize],
        )
      end
    end

    private

    sig { params(product: String).void }
    def successful_onboarding_of_product(product:)
      Billing::UpdateCustomerInBillingPlatformJob.expects(:perform_now).with(@customer, nil).once

      refute @customer.billed_via_billing_platform
      assert_equal @customer.reload.bill_cycle_day, 20

      enable_product_for_customer(customer: @customer, products: [product])

      assert @customer.reload.billed_via_billing_platform
      assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [@customer])
      assert_equal 20, @customer.reload.bill_cycle_day
    end

    sig { params(customer: Customer, products: Array).void }
    def enable_product_for_customer(customer:, products:)
      @customer.update!(billed_via_billing_platform: true)
      Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(customer_id: T.must(customer.id), products: products, previous_customer_id: nil)
    end
  end
end if GitHub.billing_enabled?
