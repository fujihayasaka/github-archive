# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipStripeRadarRiskScoreTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "validations" do
    test "requires a billing transaction" do
      score = SponsorshipStripeRadarRiskScore.new(billing_transaction: nil)
      refute_predicate score, :valid?
      assert_includes score.errors[:billing_transaction], "must exist"
    end

    test "requires a value" do
      score = SponsorshipStripeRadarRiskScore.new(value: nil)
      refute_predicate score, :valid?
      assert_includes score.errors[:value], "can't be blank"
    end
  end

  context "create_from_webhook" do
    test "creates a record from a charge succeeded webhook" do
      webhook = create(:stripe_webhook, :charge_succeeded)

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
      score = SponsorshipStripeRadarRiskScore.create_from_webhook(webhook)

      assert_predicate score, :persisted?
      assert_equal billing_transaction.id, score.billing_transaction_id
      assert_equal expected_risk_score, score.value
      assert_equal expected_outcome, score.outcome
    end

    test "creates a record from a charge failed webhook" do
      webhook = create(:stripe_webhook, :charge_failed)

      charge_id = webhook.payload.dig(:data, :object, :id)
      billing_transaction = create(:billing_transaction, :zuora, transaction_id: charge_id)

      expected_risk_score = 0
      expected_outcome = {
        "network_status" => "declined_by_network",
        "reason" => "transaction_not_allowed",
        "risk_level" => "normal",
        "risk_score" => 0,
        "seller_message" => "The bank returned the decline code `transaction_not_allowed`.",
        "type" => "issuer_declined"
      }
      score = SponsorshipStripeRadarRiskScore.create_from_webhook(webhook)

      assert_predicate score, :persisted?
      assert_equal billing_transaction.id, score.billing_transaction_id
      assert_equal expected_risk_score, score.value
      assert_equal expected_outcome, score.outcome
    end

    test "emits metrics" do
      webhook = create(:stripe_webhook, :charge_succeeded)
      metric_key = "sponsors.stripe_radar_risk_score.create_from_webhook.count"

      # fails due to missing billing transaction
      SponsorshipStripeRadarRiskScore.create_from_webhook(webhook)
      assert_dogstats_increment 1, metric_key, tags: ["success:false"]

      charge_id = webhook.payload.dig(:data, :object, :id)
      billing_transaction = create(:billing_transaction, :zuora, transaction_id: charge_id)
      SponsorshipStripeRadarRiskScore.create_from_webhook(webhook)
      assert_dogstats_increment 1, metric_key, tags: ["success:true"]
    end
  end
end
