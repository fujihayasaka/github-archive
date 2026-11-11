# typed: true
# frozen_string_literal: true

# Configurable for soft and hard limits of Organizations per Business
module Configurable::OrganizationsPerBusinessLimit
  extend T::Helpers

  requires_ancestor { Configurable }

  HARD_LIMIT_KEY = "organizations_per_business_limit"
  SOFT_LIMIT_KEY = "organizations_per_business_soft_limit"

  # Subject to product confirmation
  DEFAULT_GHES_HARD_LIMIT = 15_000
  DEFAULT_GHES_SOFT_LIMIT = 7_500
  DEFAULT_CLOUD_HARD_LIMIT = 1_000
  DEFAULT_CLOUD_SOFT_LIMIT = 500

  # The default hard limit for the number of Organizations per Business for the environment.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def default_organizations_per_business_limit
    if GitHub.single_business_environment?
      DEFAULT_GHES_HARD_LIMIT
    else
      DEFAULT_CLOUD_HARD_LIMIT
    end
  end

  # The default soft limit for the number of Organizations per Business for the environment.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def default_organizations_per_business_soft_limit
    if GitHub.single_business_environment?
      DEFAULT_GHES_SOFT_LIMIT
    else
      DEFAULT_CLOUD_SOFT_LIMIT
    end
  end

  # Get the hard limit for the number of Organizations per Business.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def organizations_per_business_limit
    config.get(HARD_LIMIT_KEY)&.to_i || default_organizations_per_business_limit
  end

  # Get the soft limit for the number of Organizations per Business.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def organizations_per_business_soft_limit
    config.get(SOFT_LIMIT_KEY)&.to_i || default_organizations_per_business_soft_limit
  end

  # Set the hard limit for the number of Organizations per Business.
  #
  # value - Integer representing the limit to set.
  # actor - User setting the limit.
  # final - Optional Boolean representing whether the limit should override
  #   values set on objects lower down in the hierarchy.
  #
  # Returns nothing.
  sig { params(value: Integer, actor: User, final: T::Boolean).void }
  def set_organizations_per_business_limit(value, actor:, final: false)
    config.set!(HARD_LIMIT_KEY, value, actor, final)
  end

  # Set the soft limit for the number of Organizations per Business.
  #
  # value - Integer representing the limit to set.
  # actor - User setting the limit.
  # final - Optional Boolean representing whether the limit should override
  #   values set on objects lower down in the hierarchy.
  #
  # Returns nothing.
  sig { params(value: Integer, actor: User, final: T::Boolean).void }
  def set_organizations_per_business_soft_limit(value, actor:, final: false)
    config.set!(SOFT_LIMIT_KEY, value, actor, final)
  end

  # Clear the hard limit for the number of Organizations per Business.
  #
  # actor: User setting the limit.
  #
  # Returns nothing.
  sig { params(actor: User).void }
  def clear_organizations_per_business_limit(actor:)
    config.delete(HARD_LIMIT_KEY, actor)
  end

  # Clear the soft limit for the number of Organizations per Business.
  #
  # actor: User setting the limit.
  #
  # Returns nothing.
  sig { params(actor: User).void }
  def clear_organizations_per_business_soft_limit(actor:)
    config.delete(SOFT_LIMIT_KEY, actor)
  end
end
