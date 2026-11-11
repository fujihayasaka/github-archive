# typed: strict
# frozen_string_literal: true

class Billing::Dispute::StripeDispute
  sig { params(dispute: Billing::Dispute).void }
  def initialize(dispute)
    @dispute = dispute
  end

  sig { returns(String) }
  def url
    "https://dashboard.stripe.com/payments/#{dispute.transaction_id}"
  end

  sig { returns(String) }
  def response_url
    "https://dashboard.stripe.com/payments/#{dispute.transaction_id}/dispute"
  end

  private

  sig { returns(Billing::Dispute) }
  attr_reader :dispute
end
