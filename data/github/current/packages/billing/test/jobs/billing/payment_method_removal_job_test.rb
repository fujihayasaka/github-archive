# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PaymentMethodRemovalJobTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  test "retries on known errors" do
    [
      Faraday::ConnectionFailed,
      Faraday::SSLError,
      Faraday::TimeoutError,
      Net::OpenTimeout,
      Net::ReadTimeout,
    ].each do |error|
      user = create(:credit_card_user)
      User.any_instance.expects(:remove_all_payment_methods).raises(error, "oh no")

      Billing::PaymentMethodRemovalJob.perform_now \
        user: user,
        actor: user
    end
  end

  test "removes all payment methods" do
    user = create :credit_card_user, plan: "pro"

    with_live_zuora("zuora/remove_all_payment_methods") do
      zuora_account_id = "2c92c0fa61789dac01619105be872892"
      user.customer.payment_method.update payment_processor_customer_id: zuora_account_id
      Billing::PaymentMethodRemovalJob.perform_now \
        user: user,
        actor: user

      refute user.reload.has_credit_card?
    end
  end
end if GitHub.billing_enabled?
