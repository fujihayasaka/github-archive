# typed: strict
# frozen_string_literal: true

module Copilot
  class Quotas
    # This returns the current quotas for all features
    # This is the free allotment for all users, not the individual user's quota
    sig { returns(T::Hash[String, Integer]) }
    def self.monthly_quotas
      # stop being dynamic when you haven't ever changed
      DEFAULT_QUOTAS
    end
  end
end
