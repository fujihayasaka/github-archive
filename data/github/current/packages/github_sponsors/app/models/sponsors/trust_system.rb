# typed: true
# frozen_string_literal: true

class Sponsors::TrustSystem
  # Public: Determine if payout info should be visible for the given sponsorable.
  # Does not assess whether the specified actor is an authorized viewer of that payout
  # info.
  #
  # actor - the User accessing payout info
  # sponsorable - the User or Organization that the actor is trying to view
  #   payout info for, whose trust will be considered
  #
  # Returns a Boolean.
  def self.enough_trust_for_payout_info?(actor:, sponsorable:)
    PayoutInfoCheck.call(actor: actor, sponsorable: sponsorable)
  end

  # Public: Determine if a sponsorship should be allowed. Does not assess whether
  # the specified actor is authorized to make the sponsorship.
  #
  # actor - the User creating the sponsorship
  # sponsor - the User or Organization funding the sponsorship
  # sponsorable - the User or Organization receiving the sponsorship
  # tier - the SponsorsTier associated with the sponsorship
  #
  # Returns a Boolean.
  def self.enough_trust_for_sponsorship?(actor:, sponsor:, sponsorable:, tier:)
    SponsorshipCheck.call(
      actor: actor,
      sponsor: sponsor,
      sponsorable: sponsorable,
      tier: tier
    )
  end
end
