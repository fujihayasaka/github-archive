# typed: true
# frozen_string_literal: true

# Configurable for the limit of BusinessTeams per Business
module Configurable
  module BusinessTeamsPerBusinessLimit
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "business_teams_per_business_limit"
    # We currently need a higher limit in test and development due to seeds that breach the production limit
    DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_LIMIT = (Rails.env.test? || Rails.env.dev?) ? 20 : 5 # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    # Get the limit for the number of BusinessTeams per Business.
    #
    # Returns Integer.
    sig { returns(Integer) }
    def business_teams_per_business_limit
      config.get(KEY)&.to_i || DEFAULT_BUSINESS_TEAMS_PER_BUSINESS_LIMIT
    end

    # Set the limit for the number of BusinessTeams per Business.
    #
    # value - Integer representing the limit to set.
    # actor - User setting the limit.
    # final - Optional Boolean representing whether the limit should override
    #   values set on objects lower downin the hierarchy.
    #
    # Returns nothing.
    sig { params(value: Integer, actor: User, final: T::Boolean).void }
    def set_business_teams_per_business_limit(value, actor:, final: false)
      config.set!(KEY, value, actor, final)
    end

    # Clear the limit for the number of BusinessTeams per Business.
    #
    # actor: User setting the limit.
    #
    # Returns nothing.
    sig { params(actor: User).void }
    def clear_business_teams_per_business_limit(actor:)
      config.delete(KEY, actor)
    end
  end
end
