# typed: true
# frozen_string_literal: true

# Configurable for the limit of BusinessTeams per Business
module Configurable
  module BusinessTeamsPerBusinessLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    HARD_LIMIT_KEY = "business_teams_per_business_limit"
    SOFT_LIMIT_KEY = "business_teams_per_business_soft_limit"
    DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_LIMIT = 2_500
    DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_SOFT_LIMIT = 1_250

    # Get the limit for the number of BusinessTeams per Business.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_teams_per_business_limit
      config.get(HARD_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_LIMIT
    end

    # Get the soft limit for the number of BusinessTeams per Business.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_teams_per_business_soft_limit
      config.get(SOFT_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_SOFT_LIMIT
    end

    # Set the limit for the number of BusinessTeams per Business.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_teams_per_business_limit(value, actor:, final: false)
      config.set!(HARD_LIMIT_KEY, value, actor, final)
    end

    # Set the soft limit for the number of BusinessTeams per Business.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_teams_per_business_soft_limit(value, actor:, final: false)
      config.set!(SOFT_LIMIT_KEY, value, actor, final)
    end

    # Clear the limit for the number of BusinessTeams per Business.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_teams_per_business_limit(actor:)
      config.delete(HARD_LIMIT_KEY, actor)
    end

    # Clear the soft limit for the number of BusinessTeams per Business.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_teams_per_business_soft_limit(actor:)
      config.delete(SOFT_LIMIT_KEY, actor)
    end
  end
end
