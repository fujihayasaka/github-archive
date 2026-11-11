# typed: true
# frozen_string_literal: true

class Stafftools::BusinessLimitsComponent < ApplicationComponent
  attr_reader :limits_target

  def initialize(limits_target:)
    @limits_target = limits_target
  end

  private

  def safeguard_limits_url
    if global_target?
      stafftools_safeguard_limits_path
    else
      stafftools_enterprise_safeguard_limits_path(limits_target.slug)
    end
  end

  def global_target?
    limits_target == GitHub
  end

  def form_url
    if global_target?
      stafftools_enterprise_limits_path
    else
      stafftools_enterprise_enterprise_limits_path(limits_target.slug)
    end
  end

  def organizations_per_business_limit
    limits_target.organizations_per_business_limit
  end

  def organizations_per_business_soft_limit
    limits_target.organizations_per_business_soft_limit
  end

  memoize def organizations_count
    return if global_target?
    limits_target.organizations_limit_counter
  end

  def organizations_current_state
    "Currently at #{number_with_delimiter(organizations_count)} of
      #{number_with_delimiter(organizations_per_business_limit)} organizations limit.".squish
  end

  def members_per_business_limit
    limits_target.members_per_business_limit
  end

  def members_per_business_soft_limit
    limits_target.members_per_business_soft_limit
  end

  memoize def members_count
    return if global_target?
    limits_target.members_limit_counter
  end

  def members_current_state
    "Currently at #{number_with_delimiter(members_count)} of
      #{number_with_delimiter(members_per_business_limit)} members limit.".squish
  end
end
