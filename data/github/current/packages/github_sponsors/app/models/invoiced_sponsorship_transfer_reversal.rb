# typed: true
# frozen_string_literal: true

class InvoicedSponsorshipTransferReversal < ApplicationRecord::Ballast
  belongs_to :invoiced_sponsorship_transfer, required: true
  belongs_to :actor, class_name: "User", required: true

  validates :amount_in_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :amount_in_cents_must_be_reversible, on: :create
  validates :stripe_transfer_reversal_id, format: { with: /\Atrr_\w+\z/ }, allow_nil: true

  attr_reader :amount_in_dollars

  delegate :stripe_transfer_id, :sponsors_listing_id, to: :invoiced_sponsorship_transfer

  def amount_in_dollars=(amount)
    @amount_in_dollars = amount
    self.amount_in_cents = Billing::Money.parse(amount).cents
  end

  def completed?
    !stripe_transfer_reversal_id.nil?
  end

  private

  def amount_in_cents_must_be_reversible
    return unless invoiced_sponsorship_transfer
    return if amount_in_cents <= T.must(invoiced_sponsorship_transfer).reversible_amount_in_cents
    errors.add(:amount_in_cents, "must be less than the reversible amount")
  end
end
