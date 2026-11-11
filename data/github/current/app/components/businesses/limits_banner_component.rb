# typed: true
# frozen_string_literal: true

class Businesses::LimitsBannerComponent < ApplicationComponent
  ORGANIZATIONS_NOTICE_NAME = "approaching_organizations_per_enterprise_limit"
  MEMBERS_NOTICE_NAME = "approaching_members_per_enterprise_limit"

  attr_reader :business, :limit_name

  def initialize(
    business:,
    limit_name:
  )
    @business = business
    @limit_name = limit_name
  end

  private

  def render?
    return false unless business.new_enterprise_platform_limits_enforced?

    reached? || approaching?
  end

  memoize def reached?
    case limit_name
    when :organizations
      business.organizations_limit_reached?
    when :members
      business.members_limit_reached?
    else
      false
    end
  end

  memoize def approaching?
    case limit_name
    when :organizations
      business.organizations_soft_limit_reached? && !business.organizations_limit_reached?
    when :members
      business.members_soft_limit_reached? && !business.members_limit_reached?
    else
      false
    end
  end

  memoize def message
    approaching_or_reached = reached? ? "has reached" : "is approaching"

    case limit_name
    when :organizations
      limit = "#{number_with_delimiter(organizations_limit)} #{"organization".pluralize(organizations_limit)}"
      extra = " and cannot add more organizations" if reached?
      "The enterprise #{approaching_or_reached} the limit of #{limit}#{extra}."
    when :members
      limit = "#{number_with_delimiter(members_limit)} #{"member".pluralize(members_limit)}"
      extra = " and cannot add more members" if reached?
      "The enterprise #{approaching_or_reached} the limit of #{limit}#{extra}."
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end

  memoize def organizations_limit
    business.organizations_limit
  end

  memoize def members_limit
    business.members_limit
  end

  def warning_dismissed?
    current_user.dismissed_business_notice?(warning_notice_name, business_id: business.id)
  end

  def dismissal_path
    enterprise_notice_path(
      business,
      notice: warning_notice_name
    )
  end

  def warning_notice_name
    case limit_name
    when :organizations
      ORGANIZATIONS_NOTICE_NAME
    when :members
      MEMBERS_NOTICE_NAME
    else
      raise ArgumentError, "unsupported limit_name '#{limit_name}'"
    end
  end
end
