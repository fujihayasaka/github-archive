# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::OrganizationMembership::MembershipSourceComponent < ApplicationComponent
  attr_reader :direct, :business_team, :organization

  def initialize(direct:, business_team: nil, organization: nil)
    @direct = direct
    @business_team = business_team
    @organization = organization
  end

  private

  def direct?
    !!direct
  end

  def business_team_link_path
    return unless business_team.present?

    if business_team.business.owner?(current_user)
      enterprise_team_path(slug: business_team.business.slug, team_slug: business_team.slug)
    elsif organization.present?
      team_path(business_team, organization: organization)
    end
  end
end
