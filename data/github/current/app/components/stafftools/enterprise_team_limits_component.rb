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

  def member_limit
    limits_target.business_team_member_limit
  end

  def organization_assignment_limit
    limits_target.business_team_organization_assignment_limit
  end
end
