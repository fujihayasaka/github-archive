# typed: strict
# frozen_string_literal: true

class SponsorsPatreonTier < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  belongs_to :sponsors_patreon_user, required: true, inverse_of: :sponsors_patreon_tiers

  has_one :sponsors_patreon_campaign_webhook, foreign_key: :campaign_id, primary_key: :campaign_id,
    inverse_of: :sponsors_patreon_tier, dependent: :destroy

  validates :campaign_id, presence: true
  validates :amount_in_cents, presence: true, uniqueness: { scope: [:sponsors_patreon_user_id, :campaign_id] }
  validates :amount_in_cents, numericality: { only_integer: true }
  validate :amount_within_limit

  scope :with_amount_in_cents, -> (cents) { where(amount_in_cents: cents) }
  scope :amount_in_cents_at_least, -> (cents) { where(arel_table[:amount_in_cents].gteq(cents)) }
  scope :amount_in_cents_less_than, -> (cents) { where(arel_table[:amount_in_cents].lt(cents)) }

  # Public: Check if an amount is a valid one for what Patreon supports and what could be represented in a
  # SponsorsTier. Allows for non-whole-dollar amounts because Patreon supports them and we can create a custom
  # SponsorsTier at a rounded amount to represent it.
  sig { params(cents: T.nilable(Integer)).returns(T::Boolean) }
  def self.valid_price?(cents:)
    return false unless cents
    cents > 0 && cents <= SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_CENTS
  end

  # Public: For use providing an interface akin to SponsorsTier.
  sig { returns Integer }
  def monthly_price_in_cents
    amount_in_cents
  end

  # Public: For use providing an interface akin to SponsorsTier.
  sig { returns Integer }
  def yearly_price_in_cents
    monthly_price_in_cents * 12
  end

  sig { returns Billing::Money }
  def to_money
    Billing::Money.new(amount_in_cents)
  end

  sig { returns String }
  def name
    return "" unless self[:amount_in_cents]
    SponsorsTier.generate_name_for(amount_in_cents, "recurring")
  end

  private

  sig { void }
  def amount_within_limit
    return unless self[:amount_in_cents]

    unless self.class.valid_price?(cents: amount_in_cents)
      errors.add(:amount_in_cents, "must be non-zero and cannot exceed #{SponsorsTier::MAX_SPONSORSHIP_AMOUNT_HUMAN}")
    end
  end
end
