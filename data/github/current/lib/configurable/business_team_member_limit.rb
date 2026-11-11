# typed: true
# frozen_string_literal: true

# Configurable for the limit of members per BusinessTeam
module Configurable
  module BusinessTeamMemberLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    HARD_LIMIT_KEY = "business_team_member_limit"
    SOFT_LIMIT_KEY = "business_team_member_soft_limit"
    DEFAULT_BUSINESS_TEAM_MEMBER_LIMIT = 5_000
    DEFAULT_BUSINESS_TEAM_MEMBER_SOFT_LIMIT = 2_500

    # Get the limit for the number of members per BusinessTeam.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_member_limit
      config.get(HARD_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAM_MEMBER_LIMIT
    end

    # Get the soft limit for the number of members per BusinessTeam.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_member_soft_limit
      config.get(SOFT_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAM_MEMBER_SOFT_LIMIT
    end

    # Set the limit for the number of members per BusinessTeam.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_member_limit(value, actor:, final: false)
      config.set!(HARD_LIMIT_KEY, value, actor, final)
    end

    # Set the soft limit for the number of members per BusinessTeam.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_member_soft_limit(value, actor:, final: false)
      config.set!(SOFT_LIMIT_KEY, value, actor, final)
    end

    # Clear the limit for the number of members per BusinessTeam.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_member_limit(actor:)
      config.delete(HARD_LIMIT_KEY, actor)
    end

    # Clear the soft limit for the number of members per BusinessTeam.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_member_soft_limit(actor:)
      config.delete(SOFT_LIMIT_KEY, actor)
    end
  end
end
