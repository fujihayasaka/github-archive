# typed: true
# frozen_string_literal: true

class Sponsors::TrustSystem::PayoutInfoCheck
  include Sponsors::TrustSystem::Enforcement
  include Sponsors::TrustSystem::Instrumentation

  def self.call(actor:, sponsorable:)
    self.new(actor: actor, sponsorable: sponsorable).call
  end

  def initialize(actor:, sponsorable:)
    @actor = actor
    @sponsorable = sponsorable
  end

  def call
    meets_trust_threshold?
  end

  private

  def meets_trust_threshold?
    if @sponsorable.untrusted_as_sponsorable?
      instrument_action_prohibited_for_sponsorable(:view_payout_info,
        actor: @actor,
        sponsorable: @sponsorable,
        listing: @sponsorable.sponsors_listing,
        listing_stafftools_metadata: @sponsorable.sponsors_listing_stafftools_metadata
      )
      !trust_enforced?(@sponsorable)
    else
      true
    end
  end
end
