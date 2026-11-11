# typed: true
# frozen_string_literal: true

module Spam
  # Accounts that must never be suspended by spam mutations, whether
  # named directly or expanded through a cascade. Server-side mirror
  # of spamurai-next's ACCOUNTS_TO_SKIP. See availability#5523,
  # github/github#434897, and platform-health#5899 (consolidation).
  module ProtectedAccounts
    IDS = [
      10137,      # ghost
      9919,       # github (organization)
      480938,     # hubot
      41898282,   # github-actions[bot]
      49699333,   # dependabot[bot]
      62310815,   # github-advanced-security[bot]
      175728472,  # copilot-pull-request-reviewer[bot]
      198982749,  # copilot-swe-agent[bot]
      242468646,  # anthropic-code-agent[bot]
      242516109,  # openai-code-agent[bot]
    ].freeze

    # Accepts a User (catches Organization via inheritance), a User-table
    # Integer ID, or nil. Business records are intentionally NOT consulted
    # (separate id space — collisions must not silently protect them).
    def self.protected?(account_or_id)
      case account_or_id
      when nil
        false
      when Integer
        IDS.include?(account_or_id)
      when User
        IDS.include?(account_or_id.id)
      else
        false
      end
    end
  end
end
