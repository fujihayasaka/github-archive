# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::AmendmentProcessedTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper
  include GitHub::ZuoraTestHelper

  fixtures do
    @webhook = create(:zuora_webhook, :amendment_processed)
  end

  context "AmendmentProcessed webhook" do
    test "no-ops if the subscription is not found in Zuora" do
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

    test "ignores for a suspended account" do
      organization = create(:organization, billing_type: "invoice")
      response = find_subscription_response(id: @webhook.subscription_id, organization_id: organization.id)

      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      organization.suspend("Did something bad")

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "raises error when organization is not invoiced" do
      organization = create(:organization, billing_type: "card")
      response = find_subscription_response(id: @webhook.subscription_id, organization_id: organization.id)

      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      exception = assert_raises(Billing::Zuora::WebhookError) { @webhook.perform }
      assert_equal "Amendment webhook received for non-invoiced organization", exception.message
      assert_predicate @webhook, :pending?
    end

    test "raises error when zuora account ids do not match" do
      organization = create(:organization, :zuora, billing_type: "invoice")
      response = find_subscription_response(id: @webhook.subscription_id, account_id: "accountId", organization_id: organization.id)

      organization.customer.update!(zuora_account_id: "invalid_account_id")

      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(response)

      exception = assert_raises(Billing::Zuora::WebhookError) { @webhook.perform }
      assert_equal "Amendment webhook account id does not match customer account id", exception.message
      assert_predicate @webhook, :pending?
    end

    test "updates an existing customer with the zuora account info if the organization already has a customer but it doens't have an account ID" do
      account_id = "zuora_account_id"
      account_number = "zuora_account_number"
      organization = create(:organization, :zuora)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
          account_id: account_id,
          account_number: account_number,
          subscription_number: "A-S00000000",
        }
      )

      organization.customer.update!(zuora_account_id: nil)
      organization.update!(billing_type: "invoice")

      @webhook.perform

      organization.customer.reload

      assert_predicate @webhook, :processed?
      assert_equal account_id, organization.customer.zuora_account_id
      assert_equal account_number, organization.customer.zuora_account_number
    end

    test "creates a new customer with the zuora account info if the organization doesn't have a customer" do
      account_id = "zuora_account_id"
      account_number = "zuora_account_number"
      organization = create(:organization, :zuora)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          organization_id: organization.id,
          id: @webhook.subscription_id,
          account_id: account_id,
          account_number: account_number,
          subscription_number: "A-S00000000",
        }
      )

      organization.customer.destroy
      organization.update!(billing_type: "invoice")

      @webhook.perform

      organization.reload

      assert_predicate @webhook, :processed?
      assert_equal account_id, organization.customer.zuora_account_id
      assert_equal account_number, organization.customer.zuora_account_number
    end

    test "updates seats" do
      account_id = "zuora_account_id"
      organization = create(:organization, :zuora, billing_type: "invoice", seats: 100)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          seats: 110,
          organization_id: organization.id,
          account_id: account_id,
          subscription_number: "A-S00000000",
        }
      )

      organization.customer.update!(zuora_account_id: account_id)
      organization.update!(billing_type: "invoice", seats: 100)

      @webhook.perform

      assert_predicate @webhook, :processed?
      assert_equal 110, organization.reload.seats
    end

    test "re-enables disabled organization" do
      account_id = "zuora_account_id"
      organization = create(:organization, :zuora, billing_type: "invoice", disabled: true)
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
          account_id: account_id,
          seats: 110,
          subscription_number: "A-S00000000",
        }
      )

      organization.customer.update!(zuora_account_id: account_id)

      @webhook.perform

      assert_predicate @webhook, :processed?
      assert organization.reload.enabled?
    end

    test "logs changes to seats, plan, plan duration, and data packs" do
      account_id = "zuora_account_id"
      organization = create(:organization, :zuora, billing_type: "invoice")
      stub_account_and_subscription(
        subscription_params: {
          success: true,
          id: @webhook.subscription_id,
          organization_id: organization.id,
          account_id: account_id,
          seats: 30,
          data_packs: 70,
          plan_name: "business_plus",
          subscription_number: "A-S00000000",
        }
      )

      events = subscribe("account.plan_change")

      organization.transactions.destroy_all
      organization.customer.update!(zuora_account_id: account_id)

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?

      # Event order is nondeterministic
      # Only check that correct number of events happen
      assert_equal 3, events.count
      assert_equal 3, organization.transactions.count
      assert_equal %w[added_seats downgraded added_asset_packs].sort,
        organization.transactions.map(&:action).sort
    end

    test "logs nothing when no changes are made" do
      data_packs = 10
      seats = 10
      plan = "business_plus"
      organization = create(:organization, billing_type: "invoice", seats: seats, plan: plan)
      stub_account_and_subscription(
        subscription_params: {
          id: @webhook.subscription_id,
          organization_id: organization.id,
          plan_name: plan,
          seats: seats,
          data_packs: data_packs,
          subscription_number: "A-S00000000",
        }
      )

      organization.build_asset_status!
      organization.asset_status.update_data_packs(quantity: data_packs, actor: organization)

      events = subscribe("account.plan_change")

      organization.transactions.destroy_all

      @webhook.perform
      organization.reload

      assert_predicate @webhook, :processed?

      assert_equal 0, events.count
      assert_equal 0, organization.transactions.count
    end

    test "synchronizes businesses" do
      business = create(:business)
      organization = create(:organization, business: business)
      account_id = business.customer.zuora_account_id
      account_number = "zuora_account_number"
      subscription_number = "zuora_subscription_number"
      seats = 3450
      data_packs = 12
      start_date = GitHub::Billing.today
      end_date = start_date + 1.year
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
          start_date: start_date,
          term_end_date: end_date,
        }
      )

      @webhook.perform

      business.reload
      organization.reload

      assert_predicate @webhook, :processed?

      assert_equal subscription_number, business.customer.sales_serve_plan_subscription.zuora_subscription_number
      assert_equal seats, business.seats
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
      account_id = "zuora_account_id"
      account_number = "zuora_account_number"
      subscription_number = "zuora_subscription_number"
      seats = 3450
      data_packs = 12
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
        }
      )
      @webhook.perform

      business.reload
      organization.reload

      assert_predicate @webhook, :processed?

      assert_equal subscription_number, business.customer.sales_serve_plan_subscription.zuora_subscription_number
      assert_equal seats, business.seats
      refute_empty business.customer.sales_serve_plan_subscription.zuora_rate_plan_charges
      # Since we don't have business-level datapacks, assign them to the first organization
      # If datapacks ever get moved to the business level then this should change to applying
      # the datapacks at that level.
      assert_equal data_packs, organization.data_packs
    end

    test "does not synchronize business if there's an account ID mismatch" do
      old_seats = 300
      business = create(:business, seats: old_seats)
      organization = create(:organization, business: business)
      account_number = "zuora_account_number"
      subscription_number = "zuora_subscription_number"
      seats = 3450
      data_packs = 12
      subscription = find_subscription_response(
        success: true,
        id: @webhook.subscription_id,
        account_id: "different_id",
        account_number: account_number,
        organization_id: nil,
        business_id: business.id,
        plan_name: "business_plus",
        seats: seats,
        data_packs: data_packs,
        subscription_number: subscription_number,
        start_date: GitHub::Billing.today,
      )
      Zuorest::Model::Subscription.expects(:find).with(@webhook.subscription_id).returns(subscription)

      assert_raises(Billing::Zuora::WebhookError) { @webhook.perform }

      business.reload
      organization.reload

      assert_predicate @webhook, :pending?
      assert_equal old_seats, business.seats
    end

    test "removes zuora information from all organizations conflicting with business zuora_account_number" do
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
        }
      )

      @webhook.perform

      business.reload
      customer.reload

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
      organization = create(:organization, billing_type: "invoice")

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
        }
      )

      @webhook.perform

      customer.reload

      refute customer.zuora_account_id
      refute customer.zuora_account_number

      assert_equal original_zuora_account_id, organization.customer.zuora_account_id
      assert_equal original_zuora_account_number, organization.customer.zuora_account_number

      increments = GitHub.dogstats.increments("billing.customer_zuora_account_number_conflict.count")
      assert_equal 1, increments.length
      assert_includes increments.first.tags, "resolved:true"
    end

    test "disassociates the customer from all organizations when a business and its organization(s) are sharing the same customer" do
      customer = create(:no_credit_card_customer)
      business = create(:business, customer: customer)
      organization = create(:organization)
      business.add_organization(organization)
      customer.organizations << organization

      assert business.reload.customer == organization.reload.customer

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
        }
      )

      @webhook.perform

      business.reload

      assert_equal original_zuora_account_id, business.customer.zuora_account_id
      assert_equal original_zuora_account_number, business.customer.zuora_account_number
      assert_empty customer.reload.organizations
    end

    test "updates the subscription for education bundles" do
      zuora_sandbox_data = {
        subscription_id: "8ad08cbd85e0d3100185e161535126b5",
        account_id: "8ad08e1a85e0d30a0185e15d00536c9f",
        account_number: "A0102178956"
      }
      webhook = create(:zuora_webhook, :amendment_processed,
        payload: {
          subscription_id: zuora_sandbox_data[:subscription_id]
        }
      )
      customer = create(:customer, :zuora,
        zuora_account_id: zuora_sandbox_data[:account_id],
        zuora_account_number: zuora_sandbox_data[:account_number]
      )
      owner = create(:business, customer: customer)

      Billing::Zuora::SalesManagedSubscription.any_instance.stubs(:enterprise?).returns(true)
      Billing::Zuora::SalesManagedSubscription.any_instance.stubs(:owner).returns(owner)

      with_live_zuora("zuora/amendment_processed/education_bundle") do
        Billing::Zuora::Webhooks::AmendmentProcessed.perform(webhook)
      end

      assert_equal "plus", owner.reload.sales_serve_plan_subscription.education_bundle
      assert owner.reload.sales_serve_plan_subscription.education_bundle?
      assert owner.reload.sales_serve_plan_subscription.education_bundle_plus?
    end
  end
end if GitHub.billing_enabled?
