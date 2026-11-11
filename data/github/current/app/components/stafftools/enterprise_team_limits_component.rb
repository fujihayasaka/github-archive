# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseTeamLimitsComponent < ApplicationComponent
  attr_reader :limits_target

  def initialize(limits_target:)
    @limits_target = limits_target
  end

  private

  def global_target?
    limits_target == GitHub
  end

  def safeguard_limits_url
    if global_target?
      stafftools_safeguard_limits_path
    else
      stafftools_enterprise_safeguard_limits_path(limits_target.slug)
    end
  end

  def form_url
    if global_target?
      stafftools_enterprise_team_limits_path
    else
      stafftools_enterprise_enterprise_team_limits_path(limits_target.slug)
    end
  end

  def teams_per_business_limit
    limits_target.business_teams_per_business_limit
  end

  def teams_per_business_soft_limit
    limits_target.business_teams_per_business_soft_limit
  end

  memoize def business_teams_count
    return if global_target?
    limits_target.business_teams.count
  end

  def business_teams_current_state
    "Currently at #{number_with_delimiter(business_teams_count)} of
      #{number_with_delimiter(teams_per_business_limit)} enterprise teams limit.".squish
  end

  def member_limit
    limits_target.business_team_member_limit
  end

  def member_soft_limit
    limits_target.business_team_member_soft_limit
  end

  def organization_assignment_limit
    limits_target.business_team_organization_assignment_limit
  end

  def organization_assignment_soft_limit
    limits_target.business_team_organization_assignment_soft_limit
  end
end
