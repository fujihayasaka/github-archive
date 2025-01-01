# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::PaymentGatewayTest < GitHub::BillingTestCase
  fixtures do
    @user = create(:user)
  end

  context ".for" do
    test "returns Stripe v3 when the type is credit card" do
      assert_equal Billing::Zuora::PaymentGateway::STRIPE_V3, Billing::Zuora::PaymentGateway.for(@user,
        type: :credit_card)
    end

    test "returns Sponsors Stripe v2 when the type is credit card and the purpose is sponsors" do
      assert_equal Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2, Billing::Zuora::PaymentGateway.for(@user,
        type: :credit_card, purpose: :sponsors)
    end

    test "returns Paypal when the type is paypal" do
      assert_equal Billing::Zuora::PaymentGateway::PAYPAL, Billing::Zuora::PaymentGateway.for(@user, type: :paypal)
    end

    test "returns Paypal when the type is paypal and the purpose is sponsors" do
      assert_equal Billing::Zuora::PaymentGateway::PAYPAL, Billing::Zuora::PaymentGateway.for(@user,
        type: :paypal, purpose: :sponsors)
    end

    test "raises an argument exception when the type is not paypal or credit card" do
      error = assert_raises ArgumentError do
        Billing::Zuora::PaymentGateway.for(@user, type: :ach)
      end
      assert_equal "Invalid gateway type ach", error.message
    end

    test "raises an argument exception when the purpose is neither general nor sponsors" do
      error = assert_raises ArgumentError do
        Billing::Zuora::PaymentGateway.for(@user, type: :credit_card, purpose: :for_funsies)
      end
      assert_equal "Invalid gateway purpose :for_funsies, expected one of :general, :sponsors", error.message
    end
  end
end
