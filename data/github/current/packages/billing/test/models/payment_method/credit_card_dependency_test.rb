# typed: true
# frozen_string_literal: true

require "test_helper"

class PaymentMethodCreditCardDependencyTest < GitHub::TestCase
  context ".credit_cards scope" do
    test "includes only credit card payment methods" do
      cc_payment_method1 = create(:payment_method)
      paypal_payment_method = create(:paypal_payment_method)
      cc_payment_method2 = create(:payment_method)

      result = PaymentMethod.credit_cards.where(id: [cc_payment_method1, paypal_payment_method, cc_payment_method2])

      assert_same_elements [cc_payment_method1, cc_payment_method2], result
      assert result.all?(&:credit_card?), "scope should stay in sync with #credit_card? method"
    end
  end
end
