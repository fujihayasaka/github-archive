# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class LogSponsorshipStripeRadarRiskScoreJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @charge_failed_webhook = create(:stripe_webhook, :charge_failed, user_id: @user.id)
  end

  setup do
    @failed_charge_id = @charge_failed_webhook.payload.dig(:data, :object, :id)
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: LogSponsorshipStripeRadarRiskScoreJob, args: [@charge_failed_webhook]
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: LogSponsorshipStripeRadarRiskScoreJob, args: [@charge_failed_webhook]
  end

  if GitHub.sponsors_enabled?
    test "creates a SponsorshipStripeRadarRiskScore for a charge_failed webhook" do
      billing_transaction = create(:billing_transaction, :zuora, transaction_id: @failed_charge_id)
      expected_risk_score = 0
      expected_outcome = {
        "network_status" => "declined_by_network",
        "reason" => "transaction_not_allowed",
        "risk_level" => "normal",
        "risk_score" => 0,
        "seller_message" => "The bank returned the decline code `transaction_not_allowed`.",
        "type" => "issuer_declined"
      }

      assert_difference(-> { SponsorshipStripeRadarRiskScore.count }) do
        LogSponsorshipStripeRadarRiskScoreJob.perform_now(@charge_failed_webhook)
      end

      score = SponsorshipStripeRadarRiskScore.last
      assert_equal billing_transaction.id, T.must(score).billing_transaction_id
      assert_equal expected_risk_score, T.must(score).value
      assert_equal expected_outcome, T.must(score).outcome
    end

    test "creates a SponsorshipStripeRadarRiskScore for a charge_succeeded webhook" do
      webhook = create(:stripe_webhook, :charge_succeeded, user_id: @user.id)
      charge_id = webhook.payload.dig(:data, :object, :id)
      billing_transaction = create(:billing_transaction, :zuora, transaction_id: charge_id)
      expected_risk_score = 15
      expected_outcome = {
        "network_status" => "approved_by_network",
        "reason" => nil,
        "risk_level" => "normal",
        "risk_score" => 15,
        "seller_message" => "Payment complete.",
        "type" => "authorized"
      }

      assert_difference(-> { SponsorshipStripeRadarRiskScore.count }) do
        LogSponsorshipStripeRadarRiskScoreJob.perform_now(webhook)
      end

      score = SponsorshipStripeRadarRiskScore.last
      assert_equal billing_transaction.id, T.must(score).billing_transaction_id
      assert_equal expected_risk_score, T.must(score).value
      assert_equal expected_outcome, T.must(score).outcome
    end

    test "no-op when no billing transaction exists for the charge" do
      assert_nil Billing::BillingTransaction.zuora.for_transaction(@failed_charge_id).first

      assert_no_difference(-> { SponsorshipStripeRadarRiskScore.count }) do
        LogSponsorshipStripeRadarRiskScoreJob.perform_now(@charge_failed_webhook)
      end
    end

  else
    test "no-op when Sponsors is not enabled" do
      create(:billing_transaction, :zuora, transaction_id: @failed_charge_id)

      assert_no_difference(-> { SponsorshipStripeRadarRiskScore.count }) do
        LogSponsorshipStripeRadarRiskScoreJob.perform_now(@charge_failed_webhook)
      end
    end
  end
end
