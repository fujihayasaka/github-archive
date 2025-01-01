# typed: true
# frozen_string_literal: true

class SponsorshipStripeRadarRiskScore < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  include Instrumentation::Model

  belongs_to :billing_transaction, required: true, class_name: "Billing::BillingTransaction",
    inverse_of: :sponsorship_stripe_radar_risk_scores

  validates :value, presence: true

  scope :for_billing_transaction, ->(billing_xact_or_id) { where(billing_transaction_id: billing_xact_or_id) }

  sig { params(webhook: Billing::StripeWebhook).returns(SponsorshipStripeRadarRiskScore) }
  def self.create_from_webhook(webhook)
    stripe_event = webhook.stripe_event
    stripe_charge = stripe_event.data.object

    charge_id = stripe_charge.id
    billing_transaction_id = Billing::BillingTransaction.for_transaction(charge_id).pluck(:id).first
    score = new(billing_transaction_id: billing_transaction_id)
    return score unless stripe_charge.is_a?(Stripe::Charge)

    outcome = stripe_charge.outcome
    score.value = outcome[:risk_score]
    score.outcome = outcome

    success = score.save
    tags = ["success:#{success}"]
    GitHub.dogstats.increment("sponsors.stripe_radar_risk_score.create_from_webhook.count", tags: tags)

    score
  end
end
