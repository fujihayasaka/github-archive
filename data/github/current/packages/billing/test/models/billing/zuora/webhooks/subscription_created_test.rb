# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::SubscriptionCreatedTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include GitHub::SalesServeZuoraWebhooksTestHelper

  setup do
    enable_feature_flag(:new_zuora_rate_plan_charges)
  end

  fixtures do
    @webhook = create(:zuora_webhook, :subscription_created)
  end

  context "SubscriptionCreated webhook" do
    test "ignores if the subscription is not found in Zuora" do
      response = find_subscription_response(success: false)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "raises an error when subscription has invalid business id" do
      response = find_subscription_response(id: @webhook.subscription_id, business_id: "fake_id")
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)
      assert_raises(ActiveRecord::RecordNotFound) { @webhook.perform }
      assert_predicate @webhook, :pending?
    end

    test "raises an error when subscription has invalid organization id" do
      response = find_subscription_response(id: @webhook.subscription_id, organization_id: "fake_id")
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)
      assert_raises(ActiveRecord::RecordNotFound) { @webhook.perform }
      assert_predicate @webhook, :pending?
    end

    test "logs changes to seats, plan, plan duration, and data packs" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
          plan_name: "business_plus",
          seats: 30,
          usage_refills_quantity: 20,
          data_packs: 70,
        }
      )

      events = subscribe("account.plan_change")

      organization.transactions.destroy_all

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      # Event order is nondeterministic
      # Only check that correct number of events happen
      assert_equal 4, events.count
      assert_equal 4, organization.transactions.count
      assert_equal %w[added_seats downgraded switched-to-yearly added_asset_packs].sort,
        organization.transactions.map(&:action).sort
    end

    test "records Zuora rate plan charges" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
        }
      )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      refute_empty organization.plan_subscription.zuora_rate_plan_charges
    end

    test "creates a plan subscription for the org if one doesn't exist" do
      start_date = Date.today
      subscription_number = "subscription number"

      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
          subscription_number: subscription_number,
          start_date: start_date,
        }
      )

      assert_difference("Billing::PlanSubscription.count", 1) { @webhook.perform }

      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal subscription_number, organization.plan_subscription.zuora_subscription_number
      assert_equal start_date, organization.plan_subscription.billing_start_date
    end

    test "reuses existing plan subscription for an org" do
      subscription_number = "subscription number"
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
          subscription_number: subscription_number,
        }
      )

      plan_subscription = create :billing_plan_subscription, user: organization

      assert_no_difference("Billing::PlanSubscription.count") { @webhook.perform }

      plan_subscription.reload

      assert_predicate @webhook, :processed?
      assert_equal subscription_number, plan_subscription.zuora_subscription_number
    end

    test "raises error when plan name is invalid" do
      plan_name = "invalid_plan_name"

      organization = create(:organization)

      response = find_subscription_response(success: true, id: @webhook.subscription_id, organization_id: organization.id, plan_name: plan_name)
      Zuorest::Model::Subscription.stubs(:find).returns(response)
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      assert_raises ActiveRecord::RecordInvalid do |exception|
        @webhook.perform
        assert_equal "Validation failed: Plan must be an Organization plan.", exception.message
      end

      assert_predicate @webhook, :pending?
    end

    test "creates customer when organization does not have one" do
      organization = create(:organization)
      account_id = "Account ID"
      account_number = "Account Number"
      end_date = Date.parse("2022-07-04")
      stub_account_and_subscription(
        subscription_params: { success: true, organization_id: organization.id, account_id: account_id, account_number: account_number, term_end_date: end_date, id: @webhook.subscription_id },
      )
      assert_nil organization.customer

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal account_id, organization.customer.zuora_account_id
      assert_equal account_number, organization.customer.zuora_account_number
      assert_equal end_date, organization.customer.billing_end_date.to_date
    end

    test "updates an existing customer with the zuora account info and end date if the organization already has a customer" do
      customer = create(:customer, zuora_account_id: "Old Account ID", zuora_account_number: "Old Account Number")
      organization = create(:organization, customer: customer)
      account_id = "Account ID"
      account_number = "Account Number"
      end_date = Date.parse("2022-07-04")
      bill_cycle_day = 5
      stub_account_and_subscription(
        subscription_params: { success: true, organization_id: organization.id, account_id: account_id, account_number: account_number, term_end_date: end_date, usage_refills_quantity: 1, id: @webhook.subscription_id },
        account_params: { partner_customer: true, bill_cycle_day: bill_cycle_day },
      )

      @webhook.perform
      customer.reload

      assert_predicate @webhook, :processed?
      assert_equal account_id, customer.zuora_account_id
      assert_equal account_number, customer.zuora_account_number
      assert_equal end_date, customer.billing_end_date.to_date
      assert_equal bill_cycle_day, customer.bill_cycle_day
      assert customer.reseller_customer?
    end

    test "syncs plan" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
          seats: 30,
          plan_name: "business_plus",
          term_end_date: Date.today + 1.year,
        }
      )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal 30, organization.seats
      assert_equal "business_plus", organization.plan.name
      assert_equal "year", organization.plan_duration
      assert_equal Date.today + 1.year, organization.billed_on
      assert_equal "invoice", organization.billing_type
      assert_equal 0, organization.billing_attempts
    end

    test "expires active coupons" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
        }
      )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_nil organization.coupon
      assert_nil organization.coupon_redemption
    end

    test "syncs data packs" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
          data_packs: 70,
        }
      )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal 70, organization.data_packs
    end

    test "syncs usage refills to organization" do
      freeze_time do
        organization = create(:organization)
        stub_account_and_subscription(
          subscription_params: {
            success: true,
            id: @webhook.subscription_id,
            organization_id: organization.id,
            usage_refills_quantity: 50,
          }
        )

        assert_difference -> { Billing::PrepaidMeteredUsageRefill.count } => 1 do
          @webhook.perform
        end
        organization.reload

        refill = Billing::PrepaidMeteredUsageRefill.last
        refill = T.must(refill)

        assert_predicate @webhook, :processed?
        assert_equal organization, refill.owner
        assert_equal 50_00, refill.amount_in_subunits
        assert_equal "USD", refill.currency_code
        assert_equal organization.next_billing_date, refill.expires_on.in_time_zone(GitHub::Billing.timezone).to_date
        assert refill.zuora_rate_plan_charge_id.present?
        assert refill.zuora_rate_plan_charge_number.present?
      end
    end

    test "syncs zuora information" do
      organization = create(:organization)
      stub_account_and_subscription(
          subscription_params: {
              success: true,
              id: @webhook.subscription_id,
              organization_id: organization.id,
              subscription_number: "valid_subscription_number",
              account_id: "zuora_account_id",
              account_number: "zuora_account_number",
            }
          )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal "valid_subscription_number", organization.plan_subscription.zuora_subscription_number
      assert_equal "zuora_account_id", organization.customer.zuora_account_id
      assert_equal "zuora_account_number", organization.customer.zuora_account_number
    end

    test "removes seats if subscription does not specify seat quantity" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
          plan_name: "gold",
        },
      )

      organization.seats = 100
      organization.save!

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal 0, organization.seats
    end

    test "does not update plan if subscription does not specify plan name" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
        },
      )

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal "silver", organization.plan.name
    end

    test "removes data packs if subscription does not specify data pack quanity" do
      organization = create(:organization)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
        },
      )

      organization.build_asset_status!
      organization.asset_status.update_data_packs(quantity: 10,
                                                  actor: organization)

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal 0, organization.data_packs
    end

    test "removes zuora information from organization conflicting with business zuora_account_number" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      business = create(:business, customer: nil)
      organization = create(:organization)

      customer = create(:no_credit_card_customer)
      customer.organizations << organization

      original_zuora_account_id = customer.zuora_account_id
      original_zuora_account_number = customer.zuora_account_number

      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          account_id: original_zuora_account_id,
          account_number: original_zuora_account_number,
          organization_id: nil,
          business_id: business.id,
          plan_name: "business_plus",
          subscription_number: SecureRandom.hex,
          start_date: GitHub::Billing.today,
        },
      )

      @webhook.perform

      business.reload
      customer.reload

      assert_predicate @webhook, :processed?

      assert_nil customer.zuora_account_id
      assert_nil customer.zuora_account_number

      assert_equal original_zuora_account_id, business.customer.zuora_account_id
      assert_equal original_zuora_account_number, business.customer.zuora_account_number

      increments = GitHub.dogstats.increments("billing.customer_zuora_account_number_conflict.count")
      assert_equal 1, increments.length
      assert_includes increments.first.tags, "resolved:true"
    end

    test "removes zuora information from existing organization customers that have the same accountId and accountNumber as the new organization" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      existing_org = create(:organization)
      organization = create(:organization)

      customer = create(:no_credit_card_customer)
      customer.organizations << existing_org

      original_zuora_account_id = customer.zuora_account_id
      original_zuora_account_number = customer.zuora_account_number

      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          account_id: original_zuora_account_id,
          account_number: original_zuora_account_number,
          organization_id: organization.id,
          business_id: nil,
          plan_name: "business_plus",
          subscription_number: SecureRandom.hex,
          start_date: GitHub::Billing.today,
        },
      )

      @webhook.perform

      customer.reload
      organization.reload

      assert_predicate @webhook, :processed?

      refute customer.zuora_account_id
      refute customer.zuora_account_number

      assert_equal original_zuora_account_id, organization.customer.zuora_account_id
      assert_equal original_zuora_account_number, organization.customer.zuora_account_number

      increments = GitHub.dogstats.increments("billing.customer_zuora_account_number_conflict.count")
      assert_equal 1, increments.length
      assert_includes increments.first.tags, "resolved:true"
    end

    test "synchronizes businesses" do
      business = create(:business)
      organization = create(:organization, business: business)
      account_id = SecureRandom.hex
      account_number = "zuora_account_number"
      subscription_number = "zuora_subscription_number"
      seats = 3450
      data_packs = 12
      end_date = Date.parse("2022-07-04")
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          account_id: account_id,
          account_number: account_number,
          organization_id: nil,
          business_id: business.id,
          plan_name: "business_plus",
          seats: seats,
          data_packs: data_packs,
          usage_refills_quantity: 10,
          subscription_number: subscription_number,
          start_date: GitHub::Billing.today,
          term_end_date: end_date,
        },
      )

      @webhook.perform

      business.reload
      organization.reload

      assert_predicate @webhook, :processed?

      assert_equal subscription_number, business.customer.sales_serve_plan_subscription.zuora_subscription_number
      assert_equal seats, business.seats
      # Zuora's `termEndDate` field is actually the first day of the next cycle
      assert_equal end_date - 1.day, business.customer.billing_end_date.to_date
      refute_empty business.customer.sales_serve_plan_subscription.zuora_rate_plan_charges
      # Since we don't have business-level datapacks, assign them to the first organization
      # If datapacks ever get moved to the business level then this should change to applying
      # the datapacks at that level.
      assert_equal data_packs, organization.data_packs

      refill = Billing::PrepaidMeteredUsageRefill.last
      refill = T.must(refill)
      assert_equal business, refill.owner
      assert_equal 10_00, refill.amount_in_subunits
      assert_equal "USD", refill.currency_code
      # Zuora's `termEndDate` field is actually the first day of the next cycle
      assert_equal end_date - 1.day, refill.expires_on

      # Enqueues a job to update skipped line items to ensure they are properly processed if necessary
      assert_enqueued_with job: Billing::UpdateSkippedMeteredLineItemsJob, args: [{ billable_owner: business }]
    end

    test "synchronizes businesses with enterprise agreements" do
      business = create(:business, :with_azure_subscription)
      organization = create(:organization, business: business)
      account_id = SecureRandom.hex
      account_number = "zuora_account_number"
      subscription_number = "zuora_subscription_number"
      seats = 3450
      data_packs = 12
      end_date = Date.parse("2022-07-04")
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          account_id: account_id,
          account_number: account_number,
          organization_id: nil,
          business_id: business.id,
          plan_name: "business_plus",
          seats: seats,
          data_packs: data_packs,
          subscription_number: subscription_number,
          start_date: GitHub::Billing.today,
          term_end_date: end_date,
        },
      )

      @webhook.perform

      business.reload
      organization.reload

      assert_predicate @webhook, :processed?

      assert_equal subscription_number, business.customer.sales_serve_plan_subscription.zuora_subscription_number
      assert_equal seats, business.seats
      # Zuora's `termEndDate` field is actually the first day of the next cycle
      assert_equal end_date - 1.day, business.customer.billing_end_date.to_date
      refute_empty business.customer.sales_serve_plan_subscription.zuora_rate_plan_charges
      # Since we don't have business-level datapacks, assign them to the first organization
      # If datapacks ever get moved to the business level then this should change to applying
      # the datapacks at that level.
      assert_equal data_packs, organization.data_packs
    end

    test "provisions education bundles correctly" do
      zuora_sandbox_subscription_id = "8ad085e285e0d3000185e14a4ef946bb"
      @webhook.update(payload: { subscription_id: zuora_sandbox_subscription_id })
      owner = create(:business)


      Billing::Zuora::SalesManagedSubscription.any_instance.stubs(:enterprise?).returns(true)
      Billing::Zuora::SalesManagedSubscription.any_instance.stubs(:owner).returns(owner)

      with_live_zuora("zuora/subscription_created/education_bundle") do
        @webhook.perform
      end

      owner.reload

      assert_predicate @webhook, :processed?
      assert_equal "essential", owner.sales_serve_plan_subscription.education_bundle
      assert owner.sales_serve_plan_subscription.education_bundle?
      assert owner.sales_serve_plan_subscription.education_bundle_essential?
    end
  end
end if GitHub.billing_enabled?
