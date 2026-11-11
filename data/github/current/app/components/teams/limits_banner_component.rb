# typed: true
# frozen_string_literal: true

class Teams::LimitsBannerComponent < ApplicationComponent
  MEMBERS_NOTICE_NAME = "approaching_members_per_org_team_limit"

  attr_reader :team, :limit_name

  def initialize(
    team:,
    limit_name:
  )
    @team = team
    @limit_name = limit_name
  end

  private

  def render?
    return false unless team.new_enterprise_platform_limits_enforced?
    return false if team.is_a?(BusinessTeam) || team.organization.nil?

    reached? || approaching?
  end

  memoize def reached?
    case limit_name
    when :members
      team.members_limit_reached?
    else
      false
    end
  end

  memoize def approaching?
    case limit_name
    when :members
      team.members_soft_limit_reached? && !team.members_limit_reached?
    else
      false
    end
  end

  memoize def message
    approaching_or_reached = reached? ? "has reached" : "is approaching"

    case limit_name
    when :members
      limit = "#{number_with_delimiter(members_limit)} #{"member".pluralize(members_limit)}"
      extra = " and cannot add more members" if reached?
      "The team #{approaching_or_reached} the limit of #{limit}#{extra}."
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end

  memoize def members_limit
    team.members_limit
  end

  def warning_dismissed?
    current_user.dismissed_organization_notice?(warning_notice_name, team.organization)
  end

  def dismissal_path
    dismiss_org_notice_path(
      team.organization,
      input: {
        organizationId: team.organization.id,
        notice: warning_notice_name
      }
    )
  end

  def warning_notice_name
    case limit_name
    when :members
      MEMBERS_NOTICE_NAME
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end
end
