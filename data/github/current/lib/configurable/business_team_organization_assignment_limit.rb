# typed: true
# frozen_string_literal: true

# Configurable for the limit of Organization assignments per BusinessTeam
module Configurable
  module BusinessTeamOrganizationAssignmentLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    HARD_LIMIT_KEY = "business_team_organization_assignment_limit"
    SOFT_LIMIT_KEY = "business_team_organization_assignment_soft_limit"
    DEFAULT_BUSINESS_TEAM_ORGANIZATION_ASSIGNMENT_LIMIT = GitHub.enterprise? ? 15_000 : 1_000
    DEFAULT_BUSINESS_TEAM_ORGANIZATION_ASSIGNMENT_SOFT_LIMIT = GitHub.enterprise? ? 7_500 : 500

    # Get the limit for the number of Organization assignments per BusinessTeam.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_organization_assignment_limit
      config.get(HARD_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAM_ORGANIZATION_ASSIGNMENT_LIMIT
    end

    # Get the soft limit for the number of Organization assignments per BusinessTeam.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_team_organization_assignment_soft_limit
      config.get(SOFT_LIMIT_KEY)&.to_i || DEFAULT_BUSINESS_TEAM_ORGANIZATION_ASSIGNMENT_SOFT_LIMIT
    end

    # Validate and set the soft and hard limits for the number of Organization assignments per BusinessTeam.
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
    def set_business_team_organization_assignment_soft_and_hard_limits!(soft_limit:, hard_limit:, actor:, final: false)
      soft, hard = Limits::Validator.validate_soft_and_hard_limits!(soft_limit: soft_limit, hard_limit: hard_limit)

      set_business_team_organization_assignment_limit(hard, actor:, final:)
      set_business_team_organization_assignment_soft_limit(soft, actor:, final:)
    end

    # Set the limit for the number of Organization assignments per BusinessTeam.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_organization_assignment_limit(value, actor:, final: false)
      config.set!(HARD_LIMIT_KEY, value, actor, final)
    end

    # Set the soft limit for the number of Organization assignments per BusinessTeam.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower down in the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_team_organization_assignment_soft_limit(value, actor:, final: false)
      config.set!(SOFT_LIMIT_KEY, value, actor, final)
    end

    # Clear the limit for the number of Organization assignments per BusinessTeam.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_organization_assignment_limit(actor:)
      config.delete(HARD_LIMIT_KEY, actor)
    end

    # Clear the soft limit for the number of Organization assignments per BusinessTeam.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_team_organization_assignment_soft_limit(actor:)
      config.delete(SOFT_LIMIT_KEY, actor)
    end
  end
end
