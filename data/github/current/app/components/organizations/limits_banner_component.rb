# typed: true
# frozen_string_literal: true

class Organizations::LimitsBannerComponent < ApplicationComponent
  TEAMS_NOTICE_NAME = "approaching_teams_per_organization_limit"
  MEMBERS_NOTICE_NAME = "approaching_members_per_organization_limit"

  attr_reader :organization, :limit_name

  def initialize(
    organization:,
    limit_name:
  )
    @organization = organization
    @limit_name = limit_name
  end

  private

  def render?
    return false unless organization.new_enterprise_platform_limits_enforced?

    reached? || approaching?
  end

  memoize def reached?
    case limit_name
    when :teams
      organization.teams_limit_reached?
    when :members
      organization.members_limit_reached?
    else
      false
    end
  end

  memoize def approaching?
    case limit_name
    when :teams
      organization.teams_soft_limit_reached? && !organization.teams_limit_reached?
    when :members
      organization.members_soft_limit_reached? && !organization.members_limit_reached?
    else
      false
    end
  end

  memoize def message
    approaching_or_reached = reached? ? "has reached" : "is approaching"

    case limit_name
    when :teams
      limit = "#{number_with_delimiter(teams_limit)} #{"team".pluralize(teams_limit)}"
      extra = " and cannot add more teams" if reached?
      "The organization #{approaching_or_reached} the limit of #{limit}#{extra}."
    when :members
      limit = "#{number_with_delimiter(members_limit)} #{"member".pluralize(members_limit)}"
      extra = " and cannot add more members" if reached?
      "The organization #{approaching_or_reached} the limit of #{limit}#{extra}."
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end

  memoize def teams_limit
    organization.teams_limit
  end

  memoize def members_limit
    organization.members_limit
  end

  def warning_dismissed?
    current_user.dismissed_organization_notice?(warning_notice_name, organization)
  end

  def dismissal_path
    dismiss_org_notice_path(
      organization,
      input: {
        organizationId: organization.id,
        notice: warning_notice_name
      }
    )
  end

  def warning_notice_name
    case limit_name
    when :teams
      TEAMS_NOTICE_NAME
    when :members
      MEMBERS_NOTICE_NAME
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end
end
