# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizerTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper
  include GitHub::LoggerHelper

  setup do
    @business = create :business, :with_github_subscription
    @generic_subscription_attributes = {
      id: SecureRandom.hex,
      account_id: SecureRandom.hex,
      account_number: SecureRandom.hex,
      owner: @business,
      seats: 2,
      subscription_number: SecureRandom.hex,
      term_start_date: GitHub::Billing.now,
      term_end_date: GitHub::Billing.now,
      active_usage_refill_rate_plan_charges: [],
      has_education_bundle?: false,
    }
  end

  context "#sync" do
    test "does not update rate plan charges for zuora subscriptions that have a future term start" do
      subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
        id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
      ))
      rate_plan_charges = build_list(:zuora_rate_plan_charge, 1, :active)
      subscription.stubs(:rate_plan_charges).returns(rate_plan_charges)

      plan_subscription = create :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: subscription.active_rate_plan_charges
      current_charge = create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_subscription)
      plan_subscription.reload

      latest_subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
        id: SecureRandom.hex,
        account_id: subscription.account_id,
        subscription_number: subscription.subscription_number,
        business_id: subscription.owner.id
      ))

      rate_plan_charges = build_list(:zuora_rate_plan_charge, 2, :active)
      latest_subscription.stubs(:rate_plan_charges).returns(rate_plan_charges)

      latest_subscription.stubs(:term_start_date).returns(GitHub::Billing.today + 1.day)

      Zuorest::Model::Account
        .expects(:find)
        .with(latest_subscription.account_id)
        .returns(find_account_response)
      Billing::Zuora::SalesManagedSubscription
        .expects(:fetch_by_subscription_id)
        .with(subscription.subscription_number)
        .returns(latest_subscription)

      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(subscription).sync

      assert_equal plan_subscription.reload.zuora_rate_plan_charges,
        subscription.active_rate_plan_charges

      if GitHub.flipper[:new_zuora_rate_plan_charges].enabled?
        assert_equal 1, plan_subscription.zuora_rate_plan_charges.count
        assert_equal current_charge.to_h,
          plan_subscription.subscription_rate_plan_charges.first.payload
      end
    end

    test "synchronizes the latest rate plan charges" do
      subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
        id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
      ))
      rate_plan_charges = build_list(:zuora_rate_plan_charge, 1, :active)
      subscription.stubs(:rate_plan_charges).returns(rate_plan_charges)
      plan_subscription = create :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: subscription.active_rate_plan_charges

      latest_subscription = Billing::Zuora::SalesManagedSubscription.new(
        find_subscription_response(
          id: SecureRandom.hex,
          account_id: subscription.account_id,
          subscription_number: subscription.subscription_number,
          business_id: subscription.owner.id
        )
      )

      rate_plan_charges = build_list(:zuora_rate_plan_charge, 2, :active)
      latest_subscription.stubs(:rate_plan_charges).returns(rate_plan_charges)
      latest_subscription.stubs(:term_start_date).returns(GitHub::Billing.today - 1.day)


      Zuorest::Model::Account
        .expects(:find)
        .with(latest_subscription.account_id)
        .returns(find_account_response)
      Billing::Zuora::SalesManagedSubscription
        .expects(:fetch_by_subscription_id)
        .with(subscription.subscription_number)
        .returns(latest_subscription)

      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(subscription).sync

      assert_equal plan_subscription.reload.zuora_rate_plan_charges,
        latest_subscription.active_rate_plan_charges

      if GitHub.flipper[:new_zuora_rate_plan_charges].enabled?
        assert_equal rate_plan_charges.count, plan_subscription.subscription_rate_plan_charges.count
        assert_equal rate_plan_charges.map(&:to_h),
          plan_subscription.subscription_rate_plan_charges.map(&:payload)
      end
    end

    test "provisions the education bundle when an education rate plan charge is present" do
      education_bundle_rate_plan_charge = stub \
        number: "C-001",
        bundle_plan: "essential"

      zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
        id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
      ))
      zuora_subscription.stubs(:education_bundle_rate_plan_charge).returns(education_bundle_rate_plan_charge)

      plan_subscription = create :billing_sales_serve_plan_subscription,
        customer: @business.customer

      Zuorest::Model::Account
        .expects(:find)
        .with(zuora_subscription.account_id)
        .returns(find_account_response)
      Billing::Zuora::SalesManagedSubscription
        .expects(:fetch_by_subscription_id)
        .with(zuora_subscription.subscription_number)
        .returns(zuora_subscription)

      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(zuora_subscription).sync

      assert_equal plan_subscription.reload.education_bundle, "essential"
    end

    test "clears existing education bundle when a bundle isn't present" do
      zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
        id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
      ))

      plan_subscription = create :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        education_bundle: "essential"

      Zuorest::Model::Account
        .expects(:find)
        .with(zuora_subscription.account_id)
        .returns(find_account_response)
      Billing::Zuora::SalesManagedSubscription
        .expects(:fetch_by_subscription_id)
        .with(zuora_subscription.subscription_number)
        .returns(zuora_subscription)

      Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(zuora_subscription).sync

      refute plan_subscription.reload.education_bundle?
      assert_equal plan_subscription.education_bundle, "none"
    end

    context "subscription includes support rate plans" do
      [
        {
          support_plan_charge_id: GitHub.zuora_github_premium_support_charge_ids.first,
          expected_support_plan: Configurable::SupportPlan::PREMIUM
        },
        {
          support_plan_charge_id: GitHub.zuora_github_premium_support_plus_charge_ids.first,
          expected_support_plan: Configurable::SupportPlan::PREMIUM_PLUS
        },
        {
          support_plan_charge_id: GitHub.zuora_github_premium_support_plus_msft_charge_ids.first,
          expected_support_plan: Configurable::SupportPlan::ENGINEERING_DIRECT
        },
        {
          support_plan_charge_id: GitHub.zuora_github_enterprise_campus_program_charge_ids.first,
          expected_support_plan: Configurable::SupportPlan::EDUCATION
        }
      ].each do |test_case|
        context "#{test_case[:expected_support_plan]} support plan charge is present" do
          context "subscription support plan is different from current support plan" do
            test "updates support plan and logs the support plan update" do
              @business.update(support_plan: Configurable::SupportPlan::STANDARD)

              expected_support_plan = test_case[:expected_support_plan]

              zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(
                find_subscription_response(
                  id: SecureRandom.hex,
                  account_id: SecureRandom.hex,
                  business_id: @business.id,
                  subscription_number: "A-S00000000",
                  support_plan_charge_id: test_case[:support_plan_charge_id]
                )
              )

              Zuorest::Model::Account
                .expects(:find)
                .with(zuora_subscription.account_id)
                .returns(find_account_response)

              Billing::Zuora::SalesManagedSubscription
                .expects(:fetch_by_subscription_id)
                .with(zuora_subscription.subscription_number)
                .returns(zuora_subscription)

              logged_attributes = {
                "code.namespace": "Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer",
                "code.function": "sync_business_attributes",
                "gh.business.id": @business.id,
                "gh.business.slug": @business.slug,
                "gh.subscription.support_plan": expected_support_plan
              }
              assert_logged GitHub.logger, **logged_attributes do
                Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(
                  zuora_subscription
                ).sync
              end

              @business.reload

              assert_equal expected_support_plan, @business.calculated_support_plan
            end
          end

          context "subscription support plan is the same as current support plan" do
            test "no update is made to the support plan and nothing is logged" do
              expected_support_plan = test_case[:expected_support_plan]

              @business.update(support_plan: expected_support_plan)

              zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(
                find_subscription_response(
                  id: SecureRandom.hex,
                  account_id: SecureRandom.hex,
                  business_id: @business.id,
                  subscription_number: "A-S00000000",
                  support_plan_charge_id: test_case[:support_plan_charge_id]
                )
              )

              @business.expects(:update).with({ support_plan: expected_support_plan }).never

              Zuorest::Model::Account
                .expects(:find)
                .with(zuora_subscription.account_id)
                .returns(find_account_response)

              Billing::Zuora::SalesManagedSubscription
                .expects(:fetch_by_subscription_id)
                .with(zuora_subscription.subscription_number)
                .returns(zuora_subscription)

              logger_attributes = {
                "code.namespace": "Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer",
                "code.function": "sync_business_attributes",
                "gh.business.id": @business.id,
                "gh.business.slug": @business.slug,
                "gh.subscription.support_plan": expected_support_plan
              }
              refute_logged GitHub.logger, **logger_attributes do
                Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(
                  zuora_subscription
                ).sync
              end

              @business.reload

              assert_equal expected_support_plan, @business.calculated_support_plan
            end
          end
        end
      end
    end

    context "subscription does not include support rate plans" do
      context "current support plan is allowed to be automatically disentitled" do
        [
          {
            current_support_plan: Configurable::SupportPlan::PREMIUM,
            expected_support_plan: Configurable::SupportPlan::STANDARD
          },
          {
            current_support_plan: Configurable::SupportPlan::PREMIUM_PLUS,
            expected_support_plan: Configurable::SupportPlan::STANDARD
          }
        ].each do |test_case|
          context "current support plan is #{test_case[:current_support_plan]}" do
            test "updates the support plan to the expected support plan and logs it" do
              current_support_plan = test_case[:current_support_plan]
              expected_support_plan = test_case[:expected_support_plan]

              @business.update(support_plan: current_support_plan)

              zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
                id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
              ))


              Zuorest::Model::Account
                .expects(:find)
                .with(zuora_subscription.account_id)
                .returns(find_account_response)

              Billing::Zuora::SalesManagedSubscription
                .expects(:fetch_by_subscription_id)
                .with(zuora_subscription.subscription_number)
                .returns(zuora_subscription)

              logged_attributes = {
                "code.namespace": Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.name,
                "code.function": "sync_business_attributes",
                "gh.business.id": @business.id,
                "gh.business.slug": @business.slug,
                "gh.business.old_support_plan": current_support_plan,
                "gh.business.new_support_plan": expected_support_plan
              }

              assert_logged GitHub.logger, **logged_attributes do
                Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(
                  zuora_subscription
                ).sync
              end

              @business.reload

              assert_equal expected_support_plan, @business.calculated_support_plan
            end
          end
        end
      end

      context "current support plan is not allowed to be automatically disentitled" do
        [
          Configurable::SupportPlan::ENGINEERING_DIRECT,
          Configurable::SupportPlan::ENGINEERING_DIR_P,
          Configurable::SupportPlan::ENGINEERING_DIR_UA,
          Configurable::SupportPlan::ENGINEERING_DIR_UP,
          Configurable::SupportPlan::EDUCATION
        ].each do |support_plan|
          context "current support plan is #{support_plan}" do
            test "support plan is not updated and nothing is logged" do
              @business.update(support_plan: support_plan)

              zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(find_subscription_response(
                id: SecureRandom.hex, account_id: SecureRandom.hex, business_id: @business.id, subscription_number: "A-S00000000"
              ))

              Zuorest::Model::Account
                .expects(:find)
                .with(zuora_subscription.account_id)
                .returns(find_account_response)

              Billing::Zuora::SalesManagedSubscription
                .expects(:fetch_by_subscription_id)
                .with(zuora_subscription.subscription_number)
                .returns(zuora_subscription)

              logger_attributes = {
                "code.namespace": Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.name,
                "code.function": "sync_business_attributes",
                "gh.business.id": @business.id,
                "gh.business.slug": @business.slug,
                "gh.business.old_support_plan": anything,
                "gh.business.new_support_plan": anything
              }
              refute_logged GitHub.logger, **logger_attributes do
                Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(
                  zuora_subscription
                ).sync
              end

              @business.reload

              assert_equal support_plan, @business.calculated_support_plan
            end
          end
        end
      end
    end
  end
end
