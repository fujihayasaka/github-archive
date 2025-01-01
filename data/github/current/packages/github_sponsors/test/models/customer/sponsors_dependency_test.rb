# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomerSponsorsDependencyTest < GitHub::TestCase
  include GitHub::Billing::CurrencyTestHelper
  include GitHub::ZuoraTestHelper

  setup do
    setup_currency_exchange
  end

  context "#low_sponsorship_credit_balance?" do
    if GitHub.sponsors_enabled?
      test "returns true when account balance is less than the threshold" do
        with_live_zuora("zuora/sponsors_invoiced_account_zero_balance_no_payment_method") do
          customer = build(:customer, :invoiced, :sponsors_invoiced, zuora_account_id: "2c92c0fb72ff6f03017301e43ee53fe2")
          assert_predicate customer, :low_sponsorship_credit_balance?
        end
      end

      test "returns true when credit balance is nil" do
        Customer.any_instance.stubs(:credit_balance).returns(nil)
        customer = build(:customer, :invoiced, :sponsors_invoiced)
        assert_predicate customer, :low_sponsorship_credit_balance?
      end

      test "returns false when account balance is right at the threshold" do
        with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method") do
          customer = build(:customer, :invoiced, :sponsors_invoiced, zuora_account_id: "2c92c0f96e63a4ee016e688d1cd53f7b")
          refute_predicate customer, :low_sponsorship_credit_balance?
        end
      end

      test "returns false when account balance exceeds the threshold" do
        Customer::SponsorsDependency.stub_const(:MINIMUM_INVOICE_AMOUNT_IN_CENTS, 100) do
          with_live_zuora("zuora/sponsors_invoiced_account_positive_balance_no_payment_method") do
            customer = build(:customer, :invoiced, :sponsors_invoiced, zuora_account_id: "2c92c0f96e63a4ee016e688d1cd53f7b")
            refute_predicate customer, :low_sponsorship_credit_balance?
          end
        end
      end

      test "returns false for general-purpose customer" do
        with_live_zuora("zuora/sponsors_invoiced_account_zero_balance_no_payment_method") do
          customer = build(:customer, :invoiced, zuora_account_id: "2c92c0fb72ff6f03017301e43ee53fe2")
          refute_predicate customer, :low_sponsorship_credit_balance?
        end
      end
    else
      test "returns false when Sponsors is disabled" do
        customer = build(:customer, :sponsors_invoiced)
        refute_predicate customer, :low_sponsorship_credit_balance?
      end
    end
  end
end
