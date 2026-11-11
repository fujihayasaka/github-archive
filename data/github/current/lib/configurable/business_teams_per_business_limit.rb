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

    # Validate and set the soft and hard limits for the number of BusinessTeams per Business.
    #
    # soft_limit - Integer representing the soft limit to set.
    # hard_limit - Integer representing the hard limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    # Raises Limits::Validator::LimitValueError.
    sig do
      params(
        soft_limit: T.any(String, Integer),
        hard_limit: T.any(String, Integer),
        actor: User,
        final: T::Boolean
      ).void
    end
    def set_business_teams_per_business_soft_and_hard_limits!(soft_limit:, hard_limit:, actor:, final: false)
      soft, hard = Limits::Validator.validate_soft_and_hard_limits!(soft_limit: soft_limit, hard_limit: hard_limit)

      set_business_teams_per_business_limit(hard, actor:, final:)
      set_business_teams_per_business_soft_limit(soft, actor:, final:)
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
