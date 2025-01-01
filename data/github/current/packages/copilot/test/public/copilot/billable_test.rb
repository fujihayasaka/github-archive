# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::BillableTest < GitHub::TestCase
  setup do
    GitHub.flipper[:copilot_for_business_free].disable
    GitHub.flipper[:strict_zuora_validation_on_metered_billable_check].enable
  end

  context "#copilot_billable?" do
    test "it is true when there is a payment method present" do
      org = create(:credit_card_organization)
      copilot_org = Copilot::Organization.new(org)
      create(:billing_plan_subscription, :zuora, user: org)

      assert copilot_org.copilot_billable?
    end

    test "it is true when there is a payment method present for the enterprise" do
      org = create(:copilot_for_business_credit_card_enabled_organization)
      copilot_org = Copilot::Organization.new(org)
      create(:billing_sales_serve_plan_subscription, customer: org.business.customer)
      org.reload

      assert copilot_org.copilot_billable?
    end

    test "it is true when the organization is invoiced" do
      org = create(:invoiced_organization)
      copilot_org = Copilot::Organization.new(org)
      create(:billing_plan_subscription, :zuora, user: org)

      assert copilot_org.copilot_billable?
    end

    test "it is true when the organization is metered via Azure" do
      customer = create(:customer, :azure, metered_via_azure: true)
      org = Copilot::Organization.new(create(:organization, plan: GitHub::Plan.free, customer: customer))

      assert org.copilot_billable?
    end

    test "it is false when there is no payment method and the organization is not invoiced" do
      org = Copilot::Organization.new(create(:organization))

      refute org.copilot_billable?
    end

    test "it is false when there is no payment method and the enterprise is not invoiced" do
      org = Copilot::Organization.new(create(:organization))

      refute org.copilot_billable?
    end

    test "it is false when the organization is invoiced but without zuora subscription" do
      org = Copilot::Organization.new(create(:invoiced_organization))

      refute org.copilot_billable?
    end

    test "it is false when the enterprise has an active enterprise agreement but no Azure subscription ID" do
      business = create(:business)
      business.enterprise_agreements.create!(agreement_id: "test", category: :visual_studio_bundle, status: :active)
      business.customer.update(
        azure_subscription_id: nil,
        azure_subscription_name: nil
      )


      refute Copilot::Business.new(business).copilot_billable?
    end

    test "it is false when metered services exist, but are locked" do
      business = create(:business)
      business.enterprise_agreements.create!(agreement_id: "test", category: :visual_studio_bundle, status: :active)
      business.lock_metered_services

      refute Copilot::Business.new(business).copilot_billable?
    end

    test "it is false when self serve billing is locked" do
      business = create(:business, :with_self_serve_payment)
      create(:billing_plan_subscription, :zuora_business, customer: business.customer)

      assert Copilot::Business.new(business).copilot_billable?

      business.disable!

      refute Copilot::Business.new(business).copilot_billable?
    end

    test "it is true when the enterprise has an active enterprise agreement and an Azure subscription ID" do
      business = create(:business)
      business.enterprise_agreements.create!(agreement_id: "test", category: :visual_studio_bundle, status: :active)
      business.customer.update(
        azure_subscription_id: "testsubid",
        azure_subscription_name: "testsub"
      )

      assert Copilot::Business.new(business).copilot_billable?
    end

    test "it is always true for businesses in Proxima" do
      on_multi_tenant_enterprise do
        biz = create(:business)
        copilot_biz = Copilot::Business.new(biz)
        assert copilot_biz.copilot_billable?
      end
    end

    test "it is always true for organizations in Proxima" do
      on_multi_tenant_enterprise do
        org = create(:organization)
        copilot_org = Copilot::Organization.new(org)
        assert copilot_org.copilot_billable?
      end
    end

    test "it is false when the organization is metered via Azure but has no Azure subscription ID" do
      customer = create(:customer)
      customer.metered_via_azure = true
      customer.save(validate: false)
      org = Copilot::Organization.new(create(:organization, plan: GitHub::Plan.free, customer: customer))

      customer.update(
        azure_subscription_id: nil,
      )


      refute org.copilot_billable?
    end

    test "it is false when the billable entity's payment method is not valid" do
      customer = create(:customer)
      customer.metered_via_azure = true
      customer.save(validate: false)

      org = Copilot::Organization.new(create(:organization, plan: GitHub::Plan.free, customer: customer))

      customer.payment_method.update(
        payment_token: "payment-token-cleared"
      )

      refute org.copilot_billable?
    end

    test "it is false when an enterprise is invoiced, but has no payment method on file" do
      customer = create(:customer, :invoiced)
      biz = Copilot::Business.new(create(:business, customer: customer))

      refute biz.copilot_billable?
    end
  end
end if GitHub.copilot_enabled?
