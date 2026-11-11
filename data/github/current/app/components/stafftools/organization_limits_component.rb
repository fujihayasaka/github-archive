# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationLimitsComponent < ApplicationComponent
  attr_reader :limits_target

  def initialize(limits_target:)
    @limits_target = limits_target
  end

  private

  def safeguard_limits_url
    if global_target?
      stafftools_safeguard_limits_path
    else
      stafftools_user_safeguard_limits_path(limits_target.login)
    end
  end

  def global_target?
    limits_target == GitHub
  end

  def form_url
    if global_target?
      stafftools_organization_limits_path
    else
      stafftools_user_organization_limits_path(limits_target.login)
    end
  end

  def teams_per_organization_limit
    limits_target.teams_per_organization_limit
  end

  def teams_per_organization_soft_limit
    limits_target.teams_per_organization_soft_limit
  end

  memoize def teams_count
    return if global_target?
    limits_target.teams_limit_counter
  end

  def teams_current_state
    "Currently at #{number_with_delimiter(teams_count)} of
      #{number_with_delimiter(teams_per_organization_limit)} teams limit.".squish
  end

  def members_per_organization_limit
    limits_target.members_per_organization_limit
  end

  def members_per_organization_soft_limit
    limits_target.members_per_organization_soft_limit
  end

  memoize def members_count
    return if global_target?
    limits_target.members_limit_counter
  end

  def members_current_state
    "Currently at #{number_with_delimiter(members_count)} of
      #{number_with_delimiter(members_per_organization_limit)} members limit.".squish
  end
end
