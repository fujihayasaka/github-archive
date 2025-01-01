# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorsGoalKind < Platform::Enums::Base
      description "The different kinds of goals a GitHub Sponsors member can have."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "TOTAL_SPONSORS_COUNT", "The goal is about reaching a certain number of sponsors.",
        value: "total_sponsors_count"
      value "MONTHLY_SPONSORSHIP_AMOUNT", "The goal is about getting a certain amount in USD " \
        "from sponsorships each month.", value: "monthly_sponsorship_amount"
    end
  end
end
