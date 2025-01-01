# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::OrganizationMembership::MembershipSourcesComponent < ApplicationComponent
  attr_reader :user, :organization

  class MembershipSource
    attr_reader :direct, :business_team

    def initialize(direct:, business_team: nil)
      @direct = direct
      @business_team = business_team
    end

    def direct?
      !!direct
    end
  end

  def initialize(user:, organization:)
    @user = user
    @organization = organization
  end

  private

  memoize def direct_membership?
    organization.member?(user, include_indirect_abilities: false)
  end

  memoize def teams_providing_indirect_membership
    ids = Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: user.id, organization_id: organization.id)
    BusinessTeam.where(id: ids)
  end

  memoize def membership_sources
    sources = []

    sources << MembershipSource.new(direct: true) if direct_membership?
    teams_providing_indirect_membership.each do |business_team|
      sources << MembershipSource.new(direct: false, business_team: business_team)
    end

    sources
  end

  memoize def indirect_membership_sources
    membership_sources.reject { |source| source.direct? }
  end

  def indirect_membership_sources_list_limit
    2
  end
end
