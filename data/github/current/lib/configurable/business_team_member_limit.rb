# typed: true
# frozen_string_literal: true

# Configurable for the limit of members per BusinessTeam
module Configurable
  module BusinessTeamMemberLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "business_team_member_limit"
    DEFAULT_BUSINESS_TEAM_MEMBER_LIMIT = 100

    # Get the limit for the number of members per BusinessTeam.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_member_limit
      config.get(KEY)&.to_i || DEFAULT_BUSINESS_TEAM_MEMBER_LIMIT
    end

    # Set the limit for the number of members per BusinessTeam.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower downin the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_member_limit(value, actor:, final: false)
      config.set!(KEY, value, actor, final)
    end

    # Clear the limit for the number of members per BusinessTeam.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_member_limit(actor:)
      config.delete(KEY, actor)
    end
  end
end
