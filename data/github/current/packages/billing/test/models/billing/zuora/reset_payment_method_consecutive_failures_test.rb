# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Zuora
    class ResetPaymentMethodConsecutiveFailuresTest < GitHub::BillingTestCase
      include GitHub::ZuoraTestHelper

      test "sets the number of consecutive failures to zero" do
        payment_method = create(
          :payment_method,
          :zuora,
          payment_token: "2c92c0f96abc17d2016abc813a986734",
        )

        with_live_zuora("zuora/reset_payment_method_consecutive_failures", match_requests_on: %i[method uri body_as_json_or_string]) do
          GitHub.zuorest_client.update_payment_method(payment_method.payment_token,
            "NumConsecutiveFailures" => 5,
          )

          reset = ResetPaymentMethodConsecutiveFailures.new(payment_method: payment_method).perform
          assert_predicate reset, :success?

          response = GitHub.zuorest_client.get_payment_method(payment_method.payment_token)
          assert_equal 0, response["NumConsecutiveFailures"]
        end
      end

      test "does nothing for non-Zuora payment methods" do
        payment_method = create(:no_credit_card_payment_method)

        GitHub.zuorest_client.expects(:update_payment_method).never

        with_live_zuora("zuora/reset_payment_method_consecutive_failures") do
          reset = ResetPaymentMethodConsecutiveFailures.new(payment_method: payment_method).perform
          refute_predicate reset, :success?
        end
      end
    end
  end
end if GitHub.billing_enabled?
