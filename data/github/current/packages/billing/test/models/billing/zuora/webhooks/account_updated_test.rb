# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::AccountUpdatedTest < GitHub::BillingTestCase
  fixtures do
    @plan_subscription = create(:billing_plan_subscription, :zuora)
    @customer = @plan_subscription.customer
    @webhook = create(
      :zuora_webhook,
      :account_updated,
      account_id: @customer.zuora_account_id,
      payload: { "AccountId" => @customer.zuora_account_id }
    )
  end

  context "#perform" do
    test "does nothing for a deleted account" do
      request = stub_request(:get, "#{GitHub.zuora_rest_server}/v1/accounts/#{@customer.zuora_account_id}")
      @plan_subscription.billable_entity.destroy

      @webhook.perform

      assert_predicate @webhook, :ignored?
      assert_not_requested(request)
    end

    test "does nothing for a suspended account" do
      request = stub_request(:get, "#{GitHub.zuora_rest_server}/v1/accounts/#{@customer.zuora_account_id}")
      @plan_subscription.billable_entity.suspend("Did something bad")

      @webhook.perform

      assert_predicate @webhook, :ignored?
      assert_not_requested(request)
    end

    test "updates the customer's attributes when a plan subscription has a customer attached" do
      Billing::Zuora::Account.any_instance.expects(:bill_cycle_day).returns(15)

      @customer.update_attribute(:bill_cycle_day, 1)

      @webhook.perform

      assert_predicate @webhook, :processed?
      assert_equal 15, @customer.reload.read_attribute(:bill_cycle_day)
    end
  end
end
