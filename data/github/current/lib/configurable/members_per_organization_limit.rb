# typed: true
# frozen_string_literal: true

# Configurable for soft and hard limits of members per Organization
module Configurable::MembersPerOrganizationLimit
  extend T::Helpers
  include Kernel

  requires_ancestor { Configurable }

  HARD_LIMIT_KEY = "members_per_organization_limit"
  SOFT_LIMIT_KEY = "members_per_organization_soft_limit"

  # Subject to product confirmation
  DEFAULT_GHES_HARD_LIMIT = 50_000
  DEFAULT_GHES_SOFT_LIMIT = 25_000
  DEFAULT_CLOUD_HARD_LIMIT = 50_000
  DEFAULT_CLOUD_SOFT_LIMIT = 25_000

  # The default hard limit for the number of members per Organization for the environment.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def default_members_per_organization_limit
    if GitHub.single_business_environment?
      DEFAULT_GHES_HARD_LIMIT
    else
      DEFAULT_CLOUD_HARD_LIMIT
    end
  end

  # The default soft limit for the number of members per Organization for the environment.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def default_members_per_organization_soft_limit
    if GitHub.single_business_environment?
      DEFAULT_GHES_SOFT_LIMIT
    else
      DEFAULT_CLOUD_SOFT_LIMIT
    end
  end

  # Get the hard limit for the number of members per Organization.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def members_per_organization_limit
    config.get(HARD_LIMIT_KEY)&.to_i || default_members_per_organization_limit
  end

  # Get the soft limit for the number of members per Organization.
  #
  # Returns Integer.
  sig { returns(Integer) }
  def members_per_organization_soft_limit
    config.get(SOFT_LIMIT_KEY)&.to_i || default_members_per_organization_soft_limit
  end

  # Validate and set the soft and hard limits for the number of members per Organization.
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
  def set_members_per_organization_soft_and_hard_limits!(soft_limit:, hard_limit:, actor:, final: false)
    soft, hard = Limits::Validator.validate_soft_and_hard_limits!(soft_limit: soft_limit, hard_limit: hard_limit)

    set_members_per_organization_limit(hard, actor:, final:)
    set_members_per_organization_soft_limit(soft, actor:, final:)
  end

  # Set the hard limit for the number of members per Organization.
  #
  # value - Integer representing the limit to set.
  # actor - User setting the limit.
  # final - Optional Boolean representing whether the limit should override
  #   values set on objects lower down in the hierarchy.
  #
  # Returns nothing.
  sig { params(value: Integer, actor: User, final: T::Boolean).void }
  def set_members_per_organization_limit(value, actor:, final: false)
    config.set!(HARD_LIMIT_KEY, value, actor, final)
  end

  # Set the soft limit for the number of members per Organization.
  #
  # value - Integer representing the limit to set.
  # actor - User setting the limit.
  # final - Optional Boolean representing whether the limit should override
  #   values set on objects lower down in the hierarchy.
  #
  # Returns nothing.
  sig { params(value: Integer, actor: User, final: T::Boolean).void }
  def set_members_per_organization_soft_limit(value, actor:, final: false)
    config.set!(SOFT_LIMIT_KEY, value, actor, final)
  end

  # Clear the hard limit for the number of members per Organization.
  #
  # actor: User setting the limit.
  #
  # Returns nothing.
  sig { params(actor: User).void }
  def clear_members_per_organization_limit(actor:)
    config.delete(HARD_LIMIT_KEY, actor)
  end

  # Clear the soft limit for the number of members per Organization.
  #
  # actor: User setting the limit.
  #
  # Returns nothing.
  sig { params(actor: User).void }
  def clear_members_per_organization_soft_limit(actor:)
    config.delete(SOFT_LIMIT_KEY, actor)
  end
end
