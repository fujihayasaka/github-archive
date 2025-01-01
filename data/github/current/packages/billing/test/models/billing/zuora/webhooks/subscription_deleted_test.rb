# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::SubscriptionDeletedTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper

  fixtures do
    @webhook = create(:zuora_webhook, :subscription_deleted)
  end

  context "SubscriptionDeleted webhook" do
    test "ignores if the the account does not have a sales_serve_plan_subscription" do
      @webhook.update(payload: { "subscription_id" => "fake_subscription_id" })

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "clears current zuora rate plan charges for an invoiced org" do
      org = create(:invoiced_organization)
      create(:billing_sales_serve_plan_subscription,
             customer: org.customer,
             zuora_rate_plan_charges: { charge_one: 4242 },
             zuora_subscription_id: @webhook.subscription_id)

      @webhook.update(payload: @webhook.payload.merge("DotcomOrgId__c" => org.id))
      @webhook.perform
      org.reload

      assert_predicate @webhook, :processed?
      assert_empty org.customer.sales_serve_plan_subscription.zuora_rate_plan_charges
    end

    test "clears current zuora rate plan charges for an enterprise (Business)" do
      biz = create(:business)
      create(:billing_sales_serve_plan_subscription,
             customer: biz.customer,
             zuora_rate_plan_charges: { charge_one: 4242 },
             zuora_subscription_id: @webhook.subscription_id)
      @webhook.update(payload: @webhook.payload.merge("DotcomEntAccountId__c" => biz.id))
      @webhook.perform
      biz.reload

      assert_predicate @webhook, :processed?
      assert_empty biz.customer.sales_serve_plan_subscription.zuora_rate_plan_charges
    end
  end
end if GitHub.billing_enabled?
