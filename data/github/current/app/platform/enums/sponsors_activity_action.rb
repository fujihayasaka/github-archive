# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsActivityAction < Platform::Enums::Base
      description "The possible actions that GitHub Sponsors activities can represent."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "NEW_SPONSORSHIP", "The activity was starting a sponsorship.",
        value: "new_sponsorship"
      value "CANCELLED_SPONSORSHIP", "The activity was cancelling a sponsorship.",
        value: "cancelled_sponsorship"
      value "TIER_CHANGE", "The activity was changing the sponsorship tier, either directly " \
        "by the sponsor or by a scheduled/pending change.", value: "tier_change"
      value "REFUND", "The activity was funds being refunded to " \
        "the sponsor or GitHub.", value: "refund"
      value "PENDING_CHANGE", "The activity was scheduling a downgrade or cancellation.",
        value: "pending_change"
      value "SPONSOR_MATCH_DISABLED", "The activity was disabling matching for a previously " \
        "matched sponsorship.", value: "sponsor_match_disabled"
    end
  end
end
