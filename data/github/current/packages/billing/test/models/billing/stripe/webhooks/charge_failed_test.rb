# typed: strict
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::ChargeFailedTest < GitHub::BillingTestCase
  test "enqueues a job to create a SponsorshipStripeRadarRiskScore later" do
    webhook = create(:stripe_webhook, :charge_failed)
    freeze_time

    assert_enqueued_with(
      job: LogSponsorshipStripeRadarRiskScoreJob,
      at: 4.hours.from_now,
      args: [webhook],
    ) do
      Billing::Stripe::Webhooks::ChargeFailed.perform(webhook)
    end
  end
end
