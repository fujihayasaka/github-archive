# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::SalesManagedSubscriptionSynchronizationHelperTest < GitHub::TestCase
  class Classy
    include Billing::Zuora::SalesManagedSubscriptionSynchronizationHelper

    attr_accessor :account
  end

  context "sync_customer_attributes_without_duplicate" do
    test "creates a licensing model transition when the subscription is updated with a metered GHEC charge" do
      customer = create(:customer, :zuora)
      business = create(:business, customer: customer)
      refute customer.metered_plan?

      subscription_stub = Billing::Zuora::SalesManagedSubscription.new(
        Zuorest::Model::Subscription.new(
          accountId: customer.zuora_account_id,
          accountNumber: customer.zuora_account_number,
          subscriptionNumber: "A-S00000000",
          ratePlans: [
            attributes_for(
              :zuora_rate_plan,
              ratePlanCharges: [
                attributes_for(:zuora_rate_plan_charge, :metered_ghec)
              ]
            ),
          ]
        )
      )
      subscription_end_date = Date.new(2021, 3, 2)

      account_stub = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account))
      )
      klass = Classy.new(subscription_stub)
      klass.account = account_stub

      klass.sync_customer_attributes_without_duplicate(customer, subscription_stub, subscription_end_date)

      assert_equal 1, customer.licensing_model_transitions.length
    end

    test "creates a licensing model transition when the subscription is updated with a non-metered GHEC charge" do
      customer = create(:customer, :zuora)
      business = create(:business, customer: customer)
      customer.update! metered_plan: true

      subscription_stub = Billing::Zuora::SalesManagedSubscription.new(
        Zuorest::Model::Subscription.new(
          accountId: customer.zuora_account_id,
          accountNumber: customer.zuora_account_number,
          subscriptionNumber: "A-S00000000",
          ratePlans: [
            attributes_for(
              :zuora_rate_plan,
              ratePlanCharges: []
            ),
          ]
        )
      )
      subscription_end_date = Date.new(2021, 3, 2)

      account_stub = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account))
      )
      klass = Classy.new(subscription_stub)
      klass.account = account_stub

      klass.sync_customer_attributes_without_duplicate(customer, subscription_stub, subscription_end_date)

      assert_equal 1, customer.licensing_model_transitions.length
    end

    test "ignore licensing model change if customer is currently on the same model" do
      customer = create(:customer, :zuora)
      customer.update! metered_plan: true

      subscription_stub = Billing::Zuora::SalesManagedSubscription.new(
        Zuorest::Model::Subscription.new(
          accountId: customer.zuora_account_id,
          accountNumber: customer.zuora_account_number,
          subscriptionNumber: "A-S00000000",
          ratePlans: [
            attributes_for(
              :zuora_rate_plan,
              ratePlanCharges: [
                attributes_for(:zuora_rate_plan_charge, :metered_ghec)
              ]
            ),
          ]
        )
      )
      subscription_end_date = Date.new(2021, 3, 2)

      account_stub = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account))
      )
      klass = Classy.new(subscription_stub)
      klass.account = account_stub

      klass.sync_customer_attributes_without_duplicate(customer, subscription_stub, subscription_end_date)

      assert_equal 0, customer.licensing_model_transitions.length
    end

    test "ignore licensing model change if customer does not have an associated business" do
      customer = create(:customer, :zuora)
      customer.update! metered_plan: true

      subscription_stub = Billing::Zuora::SalesManagedSubscription.new(
        Zuorest::Model::Subscription.new(
          accountId: customer.zuora_account_id,
          accountNumber: customer.zuora_account_number,
          subscriptionNumber: "A-S00000000",
          ratePlans: [
            attributes_for(
              :zuora_rate_plan,
              ratePlanCharges: [
                attributes_for(:zuora_rate_plan_charge, :metered_ghec)
              ]
            ),
          ]
        )
      )
      subscription_end_date = Date.new(2021, 3, 2)

      account_stub = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(:zuora_account))
      )
      klass = Classy.new(subscription_stub)
      klass.account = account_stub

      klass.sync_customer_attributes_without_duplicate(customer, subscription_stub, subscription_end_date)

      assert_equal 0, customer.licensing_model_transitions.length
    end

    test "with a duplicate customer, removes the reference to the old customer and updates the current customer" do
      existing_customer = create(:customer, :zuora)
      new_customer = create(:customer, :zuora)
      subscription_stub = Billing::Zuora::SalesManagedSubscription.new(
        Zuorest::Model::Subscription.new(
          accountId: existing_customer.zuora_account_id,
          accountNumber: existing_customer.zuora_account_number,
          subscriptionNumber: "A-S00000000",
          ratePlans: [],
        )
      )
      subscription_end_date = Date.new(2021, 3, 2)

      account_stub = Billing::Zuora::Account.new(
        Zuorest::Model::Account.new(attributes_for(
          :zuora_account,
          basicInfo: attributes_for(:zuora_account_basic_info, :partner_customer)
        ))
      )
      klass = Classy.new(subscription_stub)
      klass.account = account_stub

      refute new_customer.reseller_customer?

      assert_predicate account_stub, :partner_customer?

      klass.sync_customer_attributes_without_duplicate(new_customer, subscription_stub, subscription_end_date)

      existing_customer.reload
      assert_nil existing_customer.zuora_account_id
      assert_nil existing_customer.zuora_account_number

      assert new_customer.reload.reseller_customer?

      assert_equal subscription_stub.account_id, new_customer.zuora_account_id
      assert_equal subscription_stub.account_number, new_customer.zuora_account_number
      assert_equal account_stub.bill_cycle_day, new_customer.bill_cycle_day
    end
  end
end
