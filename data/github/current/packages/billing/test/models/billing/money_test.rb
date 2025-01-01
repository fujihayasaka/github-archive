# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::BillingMoneyTest < GitHub::BillingTestCase
  test "Billing::Money.zero doesn't equal 0" do
    assert_equal Billing::Money.zero, Billing::Money.zero
    refute_equal Billing::Money.zero, 0
  end

  test ".parse returns a ::Billing::Money instance" do
    parsed = ::Billing::Money.parse("$7.57")

    assert_equal 7_57, parsed.fractional
    assert_instance_of ::Billing::Money, parsed
  end
end
