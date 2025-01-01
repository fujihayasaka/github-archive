# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::AccountUsageTest < GitHub::TestCase
  context "#account_id" do
    test "returns an integer id" do
      account_usage = build(:billing_account_usage)

      assert_equal account_usage.account_id, 1
    end
  end

  context "#product_usages" do
    test "returns an array of Billing::Usage::ProductUsage objects" do
      account_usage = build(:billing_account_usage)

      assert account_usage.product_usages.is_a?(Array)
      assert account_usage.product_usages.all?(::Billing::Usage::ProductUsage)
    end
  end
end
