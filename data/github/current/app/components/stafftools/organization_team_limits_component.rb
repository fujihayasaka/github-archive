# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationTeamLimitsComponent < ApplicationComponent
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
      stafftools_organization_team_limits_path
    else
      stafftools_user_organization_team_limits_path(limits_target.login)
    end
  end

  def members_per_org_team_limit
    limits_target.members_per_org_team_limit
  end

  def members_per_org_team_soft_limit
    limits_target.members_per_org_team_soft_limit
  end
end
