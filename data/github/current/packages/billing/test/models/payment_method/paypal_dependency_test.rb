# typed: true
# frozen_string_literal: true

require "test_helper"

class PaymentMethodPaypalDependencyTest < GitHub::TestCase
  context ".paypal scope" do
    test "includes only PayPal payment methods" do
      paypal_payment_method1 = create(:paypal_payment_method)
      cc_payment_method = create(:payment_method)
      paypal_payment_method2 = create(:paypal_payment_method)

      result = PaymentMethod.paypal.where(id: [paypal_payment_method1, cc_payment_method, paypal_payment_method2])

      assert_same_elements [paypal_payment_method1, paypal_payment_method2], result
      assert result.all?(&:paypal?), "scope should stay in sync with #paypal? method"
    end
  end
end
