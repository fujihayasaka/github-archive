# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::TransferFailedTest < GitHub::BillingTestCase
  test "reports the failure to Datadog" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_failed,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
      },
    )

    Billing::Stripe::Webhooks::TransferFailed.perform(webhook)

    increments = GitHub.dogstats.increments("stripe.transfer_failed")

    assert_equal 1, increments.count
  end
end
