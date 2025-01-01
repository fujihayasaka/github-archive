# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Public::Product::ProductIdentifierTest < GitHub::TestCase
  fixtures do
    @copilot_monthly = Billing::Public::Product::ProductIdentifier.new(
                        product_type: "github.copilot",
                        product_key: "v0",
                        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze

    @copilot_yearly = Billing::Public::Product::ProductIdentifier.new(
                        product_type: "github.copilot",
                        product_key: "v0",
                        billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Year).freeze
  end

  context "#==" do
    test "two product identiers are structurally the same" do
      new_copilot_monthly = Billing::Public::Product::ProductIdentifier.new(
                              product_type: "github.copilot",
                              product_key: "v0",
                              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze


      assert @copilot_monthly == new_copilot_monthly
    end

    test "two product identiers are structurally not the same" do
      refute @copilot_monthly == @copilot_yearly
    end
  end

  context "#same?" do
    test "two product identiers are the same when all there fields are the same" do
      new_copilot_monthly = Billing::Public::Product::ProductIdentifier.new(
                              product_type: "github.copilot",
                              product_key: "v0",
                              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze

      assert @copilot_monthly.same?(new_copilot_monthly)
    end

    test "two product identiers are not the same when product type is different" do
      ghas_monthly = Billing::Public::Product::ProductIdentifier.new(
                              product_type: "github.ghas",
                              product_key: "v0",
                              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze

      refute @copilot_monthly.same?(ghas_monthly)
    end

    test "two product identiers are not the same when product key is different" do
      copilot_v9_monthly = Billing::Public::Product::ProductIdentifier.new(
                              product_type: "github.copilot",
                              product_key: "v9",
                              billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze

      refute @copilot_monthly.same?(copilot_v9_monthly)
    end

    test "two product identiers are not the same when billing cycle is different (by default)" do
      refute @copilot_monthly.same?(@copilot_yearly)
    end

    test "two product identiers are the same when billing cycle is different and match_billing_cycle is false" do
      assert @copilot_monthly.same?(@copilot_yearly, match_billing_cycle: false)
    end
  end
end
